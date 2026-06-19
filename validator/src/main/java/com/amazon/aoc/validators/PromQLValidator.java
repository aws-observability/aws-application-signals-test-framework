/*
 * Copyright Amazon.com, Inc. or its affiliates.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 * You may not use this file except in compliance with the License.
 * A copy of the License is located at
 *
 *  http://aws.amazon.com/apache2.0
 *
 * or in the "license" file accompanying this file. This file is distributed
 * on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
 * express or implied. See the License for the specific language governing
 * permissions and limitations under the License.
 */

package com.amazon.aoc.validators;

import com.amazon.aoc.exception.BaseException;
import com.amazon.aoc.exception.ExceptionCode;
import com.amazon.aoc.fileconfigs.FileConfig;
import com.amazon.aoc.helpers.MustacheHelper;
import com.amazon.aoc.helpers.RetryHelper;
import com.amazon.aoc.models.Context;
import com.amazon.aoc.models.ValidationConfig;
import com.amazon.aoc.services.PromQLService;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.common.annotations.VisibleForTesting;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;
import lombok.extern.log4j.Log4j2;

/**
 * Validates Service Events OTLP metrics (`count` for EndpointErrorMetric and
 * `service.function.duration` for FunctionCall) by running a PromQL query against the CloudWatch
 * Prometheus-compatible endpoint and asserting that at least one returned series matches every
 * expected label in the expected-data template.
 *
 * <p>These metrics are ingested as native OTLP metrics with no fixed CloudWatch namespace, so they
 * cannot be retrieved by the namespace+dimension GetMetricData path that {@link CWMetricValidator}
 * uses. The expected template is a JSON array whose objects' keys are PromQL label names (e.g.
 * {@code Telemetry.Source}, {@code operation}) and whose values are regex patterns, mirroring the
 * regex-per-field convention of {@link CWLogValidator}.
 *
 * <p>The PromQL query itself lives in {@code validationConfig.promQlQuery} and is the only place the
 * metric name is pinned. CloudWatch's PromQL surface exposes OTLP datapoint attributes either bare
 * ({@code operation}) or prefixed ({@code @datapoint.operation}); a single label key in the
 * expected template is therefore matched against both the bare key and its {@code @datapoint.}
 * prefixed form so the test does not break on either representation.
 */
@Log4j2
public class PromQLValidator implements IValidator {
  private static final int DEFAULT_MAX_RETRY_COUNT = 40;
  private static final String DATAPOINT_PREFIX = "@datapoint.";
  private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

  private final MustacheHelper mustacheHelper = new MustacheHelper();
  private Context context;
  private ValidationConfig validationConfig;
  private FileConfig expectedMetricTemplate;
  private PromQLService promQLService;
  private int maxRetryCount;

  public PromQLValidator(PromQLService promQLService) {
    this.promQLService = promQLService;
  }

  @Override
  public void init(
      Context context, ValidationConfig validationConfig, FileConfig expectedMetricTemplate)
      throws Exception {
    this.context = context;
    this.validationConfig = validationConfig;
    this.expectedMetricTemplate = expectedMetricTemplate;
    this.maxRetryCount = DEFAULT_MAX_RETRY_COUNT;
  }

  @Override
  public void validate() throws Exception {
    final String promQlQuery = renderQuery(this.validationConfig.getPromQlQuery());
    final List<Map<String, String>> expectedSeriesArray = this.getExpectedSeries();
    log.info("Expected PromQL series labels: {}", expectedSeriesArray);

    RetryHelper.retry(
        this.maxRetryCount,
        () -> {
          JsonNode response = promQLService.query(promQlQuery);
          JsonNode results = response.path("data").path("result");

          if (!results.isArray() || results.size() == 0) {
            log.info("PromQL query returned no series yet for: {}", promQlQuery);
            throw new BaseException(ExceptionCode.EXPECTED_METRIC_NOT_FOUND);
          }

          // Every expected label-set in the template must be satisfied by at least one returned
          // series.
          for (Map<String, String> expectedSeries : expectedSeriesArray) {
            boolean matched = false;
            for (JsonNode series : results) {
              if (seriesMatches(series, expectedSeries)) {
                matched = true;
                break;
              }
            }
            if (!matched) {
              log.error(
                  "PromQL Validation Failure: no returned series matched expected labels {}",
                  expectedSeries);
              throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
            }
          }
        });

    log.info("PromQL validation passed for query {}", promQlQuery);
  }

  /** Substitute the small set of supported placeholders into the PromQL query string. */
  private String renderQuery(String query) {
    if (query == null) {
      return null;
    }
    return query
        .replace("{{serviceName}}", context.getServiceName() != null ? context.getServiceName() : "")
        .replace("{{region}}", context.getRegion() != null ? context.getRegion() : "");
  }

  /**
   * Checks whether a single Prometheus series satisfies all expected label regexes. Each expected
   * key is matched against the series' {@code metric} map at both the bare key and its
   * {@code @datapoint.}-prefixed form, to tolerate CloudWatch's two OTLP-attribute label spellings.
   */
  private boolean seriesMatches(JsonNode series, Map<String, String> expectedLabels) {
    JsonNode metric = series.path("metric");
    for (Map.Entry<String, String> expected : expectedLabels.entrySet()) {
      String key = expected.getKey();
      Pattern pattern = Pattern.compile(expected.getValue());

      // Jackson looks up the literal field name, so dotted keys like "Telemetry.Source" and
      // "function.name" resolve directly. CloudWatch exposes OTLP datapoint attributes bare; some
      // surfaces prefix them with "@datapoint.", so fall back to that spelling too.
      JsonNode actualValueNode = metric.path(key);
      if (actualValueNode.isMissingNode()) {
        actualValueNode = metric.path(DATAPOINT_PREFIX + key);
      }
      if (actualValueNode.isMissingNode()) {
        return false;
      }
      if (!pattern.matcher(actualValueNode.asText()).find()) {
        return false;
      }
    }
    return true;
  }

  /**
   * Parse the expected-data template (a JSON array of label-name to regex maps) with Jackson so
   * that dotted label names such as {@code Telemetry.Source} stay literal. A path-flattening parser
   * would mis-split those keys on the dot.
   */
  private List<Map<String, String>> getExpectedSeries() throws Exception {
    String renderedTemplate = mustacheHelper.render(this.expectedMetricTemplate, context);
    return OBJECT_MAPPER.readValue(
        renderedTemplate, new TypeReference<List<Map<String, String>>>() {});
  }

  @VisibleForTesting
  public void setPromQLService(PromQLService promQLService) {
    this.promQLService = promQLService;
  }

  @VisibleForTesting
  public void setMaxRetryCount(int maxRetryCount) {
    this.maxRetryCount = maxRetryCount;
  }
}
