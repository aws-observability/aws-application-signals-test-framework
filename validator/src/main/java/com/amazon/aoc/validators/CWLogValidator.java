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
import com.amazon.aoc.services.CloudWatchService;
import com.amazonaws.services.logs.model.FilteredLogEvent;
import com.github.wnameless.json.flattener.FlattenMode;
import com.github.wnameless.json.flattener.JsonFlattener;
import com.github.wnameless.json.flattener.JsonifyArrayList;

import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import com.google.common.annotations.VisibleForTesting;
import lombok.extern.log4j.Log4j2;

@Log4j2
public class CWLogValidator implements IValidator {
  private static int DEFAULT_MAX_RETRY_COUNT = 40;

  private MustacheHelper mustacheHelper = new MustacheHelper();
  private Context context;
  private ValidationConfig validationConfig;
  private FileConfig expectedLog;
  private CloudWatchService cloudWatchService;
  private int maxRetryCount;

  @Override
  public void validate() throws Exception {
    log.info("Start CW Log Validation for path {}", validationConfig.getHttpPath());

    // Get expected values for log attributes we want to check
    JsonifyArrayList<Map<String, Object>> expectedAttributesArray = this.getExpectedAttributes();
    log.info("Values of expected logs: {}", expectedAttributesArray);

    RetryHelper.retry(
      this.maxRetryCount,
      () -> {
        // Iterate through each expected template to check if the log is present
        for (Map<String, Object> expectedAttributes : expectedAttributesArray) {
          // All attributes are in REGEX for preciseness except operation, remoteService and
          // remoteOperation
          // which are in normal text as they are needed for
          // the filter expressions for retrieving the actual logs.
          log.info("Searching for expected log: {}", expectedAttributes);
          Map<String, Object> actualLog;

          if (validationConfig.getCwLogFilterPattern() != null) {
            // Use custom filter pattern from validation config
            String customPattern = validationConfig.getCwLogFilterPattern()
                .replace("{{serviceName}}", context.getServiceName())
                .replace("{{traceId}}", context.getTraceId() != null ? context.getTraceId() : "")
                .replace("{{locationHash}}",
                    context.getLocationHash() != null ? context.getLocationHash() : "");
            actualLog = this.getActualAwsOtlpLog(Arrays.asList(customPattern));
          } else if (isAwsOtlpLog(expectedAttributes)) {
            String otlpLogFilterPattern = String.format(
                "{ ($.resource.attributes.['service.name'] = \"%s\") && ($.body = \"This is a custom log for validation testing\") }",
                context.getServiceName()
            );
            String addTraceIdFilter = (context.getTraceId() != null ? "&& ($.traceId = \"" + context.getTraceId() + "\") " : "");
            String genAILogFilterPattern = String.format(
                "{ ($.resource.attributes.['service.name'] = \"%s\") " +
                "&& ($.body.output.messages[0].role = \"assistant\") " +
                "&& ($.body.input.messages[0].role = \"user\") " +
                "&& ($.body.output.messages[1] NOT EXISTS) " +
                "&& ($.body.input.messages[1] NOT EXISTS) " +
                "%s" +
                "}",
                context.getServiceName(),
                addTraceIdFilter
            );
            actualLog = this.getActualAwsOtlpLog(Arrays.asList(otlpLogFilterPattern, genAILogFilterPattern));            
          } else {
            String operation = (String) expectedAttributes.get("Operation");
            String remoteService = (String) expectedAttributes.get("RemoteService");
            String remoteOperation = (String) expectedAttributes.get("RemoteOperation");
            String remoteResourceType = (String) expectedAttributes.get("RemoteResourceType");
            String remoteResourceIdentifier = (String) expectedAttributes.get("RemoteResourceIdentifier");

           // Parsing unique identifiers in OTLP spans
            if (operation == null) {
              operation = (String) expectedAttributes.get("attributes[\\\"aws.local.operation\\\"]");
              remoteService = (String) expectedAttributes.get("attributes[\\\"aws.remote.service\\\"]");
              remoteOperation = (String) expectedAttributes.get("attributes[\\\"aws.remote.operation\\\"]");
              // Runtime metrics have no operation at all, we must ensure we are in the proper use case
              if (operation != null) {
                actualLog = this.getActualOtelSpanLog(operation, remoteService, remoteOperation);
              } else {
                // No operation at all -> Runtime metric
                actualLog =
                  this.getActualLog(operation, remoteService, remoteOperation, remoteResourceType, remoteResourceIdentifier);
              }
            }
            else {
              actualLog =
                this.getActualLog(operation, remoteService, remoteOperation, remoteResourceType, remoteResourceIdentifier);
            }
          }
          String actualLogStr = actualLog != null ? actualLog.toString() : "null";
          // DEBUG(di-body-stack): raised from 2000 -> 20000. body.stack sits past the 2000-char
          // cutoff, so the value under test was never visible in CI logs.
          log.info("Value of an actual log: {}", actualLogStr.length() > 20000 ? actualLogStr.substring(0, 20000) + "...(truncated)" : actualLogStr);
          log.debug("Value of an actual log: {}", actualLogStr);

          if (actualLog == null) throw new BaseException(ExceptionCode.EXPECTED_LOG_NOT_FOUND);

          validateLogs(expectedAttributes, actualLog);
        }
      });

    log.info("Log validation is passed for path {}", validationConfig.getHttpPath());
  }

  private void validateLogs(Map<String, Object> expectedAttributes, Map<String, Object> actualLog)
      throws Exception {
    for (Map.Entry<String, Object> entry : expectedAttributes.entrySet()) {
      String expectedKey = entry.getKey();
      Object expectedValue = entry.getValue();

      if (!actualLog.containsKey(expectedKey)) {
        log.error("Log Validation Failure: Key {} does not exist", expectedKey);
        throw new BaseException(ExceptionCode.EXPECTED_LOG_NOT_FOUND);
      }

      Pattern pattern = Pattern.compile(expectedValue.toString());
      String actualValueStr = actualLog.get(expectedKey).toString();
      Matcher matcher = pattern.matcher(actualValueStr);

      if (!matcher.find()) {
        log.error(
          "Log Validation Failure: Value for Key: {} was expected to be: {}, but actual was: {}",
          expectedKey,
          expectedValue,
          actualLog.get(expectedKey));
        // DEBUG(di-body-stack): the failure line above has repeatedly shown an expected regex that
        // *does* match the actual value printed beside it, which should be impossible since both
        // come from the same object. Dump the exact strings being compared, with lengths and a
        // char-code view, to expose invisible differences (unicode escapes, NBSP, zero-width chars,
        // CR, smart quotes) and to confirm which value the matcher actually ran against.
        log.error("DEBUG_CMP key={}", expectedKey);
        log.error("DEBUG_CMP regex.len={} regex.raw=[{}]", expectedValue.toString().length(), expectedValue);
        log.error("DEBUG_CMP actual.len={} actual.raw=[{}]", actualValueStr.length(), actualValueStr);
        log.error("DEBUG_CMP actual.class={}", actualLog.get(expectedKey).getClass().getName());
        log.error("DEBUG_CMP rematch.find={}", Pattern.compile(expectedValue.toString()).matcher(actualValueStr).find());
        log.error("DEBUG_CMP regex.codes={}", describeChars(expectedValue.toString()));
        log.error("DEBUG_CMP actual.codes={}", describeChars(actualValueStr));
        throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
      }
    }
  }

  /**
   * DEBUG(di-body-stack): render any non-ASCII / non-printable character as \\uXXXX so that
   * invisible mismatches between the expected regex and the actual value are visible in CI logs.
   * ASCII printables are emitted as-is to keep the output readable.
   */
  private static String describeChars(String s) {
    StringBuilder sb = new StringBuilder();
    for (int i = 0; i < s.length(); i++) {
      char c = s.charAt(i);
      if (c >= 0x20 && c < 0x7F) {
        sb.append(c);
      } else {
        sb.append(String.format("\\u%04X", (int) c));
      }
    }
    return sb.toString();
  }

  private JsonifyArrayList<Map<String, Object>> getExpectedAttributes() throws Exception {
    JsonifyArrayList<Map<String, Object>> flattenedJsonMapForExpectedLogArray = null;
    String jsonExpectedLog = mustacheHelper.render(this.expectedLog, context);

    try {
      // flattened JSON object to a map while keeping the arrays
      Map<String, Object> flattenedJsonMapForExpectedLog =
        new JsonFlattener(jsonExpectedLog)
          .withFlattenMode(FlattenMode.KEEP_ARRAYS)
          .flattenAsMap();

      flattenedJsonMapForExpectedLogArray =
              (JsonifyArrayList) flattenedJsonMapForExpectedLog.get("root");
    } catch (Exception e) {
      e.printStackTrace();
    }

    return flattenedJsonMapForExpectedLogArray;
  }

  private boolean isAwsOtlpLog(Map<String, Object> expectedAttributes) {
    // OTLP SigV4 logs have 'body' as a top-level attribute
    boolean hasBodyKey = expectedAttributes.keySet().stream()
        .anyMatch(key -> key.startsWith("body"));

    return expectedAttributes.containsKey("severityNumber") && 
           expectedAttributes.containsKey("severityText") &&
           hasBodyKey;
  }

  private Map<String, Object> getActualLog(
    String operation, String remoteService, String remoteOperation, String remoteResourceType, String remoteResourceIdentifier) throws Exception {
    String dependencyFilter = null;

    // Dependency calls will have the remoteService and remoteOperation attribute, but service calls
    // will not. A service call will have
    // null remoteService and null remoteOperation and the filter expression must be adjusted
    // accordingly.
    if (remoteService == null && remoteOperation == null) {
      dependencyFilter = "&& ($.RemoteService NOT EXISTS) && ($.RemoteOperation NOT EXISTS)";
    } else {
      dependencyFilter = String.format(" && ($.RemoteService = \"%s\") && ($.RemoteOperation = \"%s\")", remoteService, remoteOperation);
    }

    if (remoteResourceType != null && remoteResourceIdentifier != null) {
      dependencyFilter += String.format(" && ($.RemoteResourceType = %%%s%%) && ($.RemoteResourceIdentifier = %%%s%%)", remoteResourceType, remoteResourceIdentifier);
    }

    if (operation != null) {
      dependencyFilter += String.format(" && ($.Operation = \"%s\")", operation);
    } else {
      // runtime metrics don't have Operation
      dependencyFilter += "&& ($.Operation NOT EXISTS)";
    }

    String filterPattern = String.format("{ ($.Service = %s) %s }", context.getServiceName(), dependencyFilter);
    log.info("Filter Pattern for Log Search: " + filterPattern);

    List<FilteredLogEvent> retrievedLogs =
      this.cloudWatchService.filterLogs(
        context.getLogGroup(),
        filterPattern,
        System.currentTimeMillis() - TimeUnit.MINUTES.toMillis(5),
        10);

    if (retrievedLogs == null || retrievedLogs.isEmpty()) {
      throw new BaseException(ExceptionCode.EMPTY_LIST);
    }

    return JsonFlattener.flattenAsMap(retrievedLogs.get(0).getMessage());
  }

  private Map<String, Object> getActualOtelSpanLog(String operation, String remoteService, String remoteOperation) throws Exception {
    String dependencyFilter = null;

    if (operation != null) {
      dependencyFilter = String.format("&& ($.attributes.['aws.local.operation'] = \"%s\")", operation);
    }
    if (remoteService != null) {
      dependencyFilter += String.format("&& ($.attributes.['aws.remote.service'] = \"%s\")", remoteService);
    } else {
      dependencyFilter += "&& ($.attributes.['aws.remote.service'] NOT EXISTS)";
    }
    if (remoteOperation != null) {
      dependencyFilter += String.format("&& ($.attributes.['aws.remote.operation'] = \"%s\")", remoteOperation);
    } else {
      dependencyFilter += "&& ($.attributes.['aws.remote.operation'] NOT EXISTS)";
    }

    String filterPattern = String.format("{ ($.attributes.['aws.local.service'] = %s) %s }", context.getServiceName(), dependencyFilter);
    log.info("Filter Pattern for Log Search: " + filterPattern);

    List<FilteredLogEvent> retrievedLogs =
      this.cloudWatchService.filterLogs(
        context.getLogGroup(),
        filterPattern,
        System.currentTimeMillis() - TimeUnit.MINUTES.toMillis(5),
        10);

    if (retrievedLogs == null || retrievedLogs.isEmpty()) {
      throw new BaseException(ExceptionCode.EMPTY_LIST);
    }

    return JsonFlattener.flattenAsMap(retrievedLogs.get(0).getMessage());
  }

  private Map<String, Object> getActualAwsOtlpLog(List<String> filterPatterns) throws Exception {
    log.info("Filter patterns {}", filterPatterns);

    List<FilteredLogEvent> retrievedLogs = null;

    for (String pattern : filterPatterns) {
      log.info("Attempting filter Pattern for OTLP Log Search: {}", pattern);

      retrievedLogs = this.cloudWatchService.filterLogs(
          context.getLogGroup(),
          pattern,
          System.currentTimeMillis() - TimeUnit.MINUTES.toMillis(5),
          10);
          
      if (retrievedLogs != null && !retrievedLogs.isEmpty()) {
        log.info("Found logs for filter pattern {}", pattern);
        break;
      }
    }

    if (retrievedLogs == null || retrievedLogs.isEmpty()) {
      throw new BaseException(ExceptionCode.EMPTY_LIST);
    }

    // DEBUG(di-body-stack): filterLogs() fetches up to 10 events but we only ever validate
    // get(0). If several snapshots match the filter, we may be validating a different event
    // than the one whose values get reported. Log how many came back, and the identity +
    // body.stack of each, so "wrong event selected" can be distinguished from "body differs".
    log.error("DEBUG_SEL retrievedLogs.size={}", retrievedLogs.size());
    for (int i = 0; i < retrievedLogs.size(); i++) {
      String msg = retrievedLogs.get(i).getMessage();
      Map<String, Object> f =
          new JsonFlattener(msg).withFlattenMode(FlattenMode.KEEP_ARRAYS).flattenAsMap();
      Object stack = f.get("body.stack");
      log.error(
          "DEBUG_SEL[{}] ts={} snapshot_id={} location_hash={} method={} stack.class={} body.stack={}",
          i,
          retrievedLogs.get(i).getTimestamp(),
          f.get("attributes[\\\"aws.di.snapshot_id\\\"]"),
          f.get("attributes[\\\"aws.di.location_hash\\\"]"),
          f.get("attributes[\\\"aws.di.method_name\\\"]"),
          stack == null ? "null" : stack.getClass().getName(),
          stack);
    }
    log.error("DEBUG_SEL selecting index 0");

    return new JsonFlattener(retrievedLogs.get(0).getMessage())
             .withFlattenMode(FlattenMode.KEEP_ARRAYS)
             .flattenAsMap();
  }

  @Override
  public void init(
      Context context,
      ValidationConfig validationConfig,
      FileConfig expectedLogTemplate)
      throws Exception {
    this.context = context;
    this.validationConfig = validationConfig;
    this.expectedLog = expectedLogTemplate;
    this.cloudWatchService = new CloudWatchService(context.getRegion());
    this.maxRetryCount = DEFAULT_MAX_RETRY_COUNT;
  }

  @VisibleForTesting
  public void setCloudWatchService(CloudWatchService cloudWatchService) {
    this.cloudWatchService = cloudWatchService;
  }

  @VisibleForTesting
  public void setMaxRetryCount(int maxRetryCount) {
    this.maxRetryCount = maxRetryCount;
  }
}
