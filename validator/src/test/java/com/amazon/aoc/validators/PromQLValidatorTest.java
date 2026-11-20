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

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.amazon.aoc.exception.BaseException;
import com.amazon.aoc.exception.ExceptionCode;
import com.amazon.aoc.fileconfigs.LocalPathExpectedTemplate;
import com.amazon.aoc.models.Context;
import com.amazon.aoc.models.ValidationConfig;
import com.amazon.aoc.services.PromQLService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.DisabledIf;

/**
 * Unit tests for {@link PromQLValidator}. The PromQL HTTP call is mocked so the tests exercise the
 * label-matching and {@code __value__} datapoint-assertion logic against canned Prometheus
 * responses. Disabled on Windows because the template is loaded from a {@code file://} path.
 */
@DisabledIf("isWindows")
public class PromQLValidatorTest {
  private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();
  private static final String TEMPLATE_ROOT =
      "file://" + System.getProperty("user.dir") + "/src/test/test-resources/";
  private static final String EXPECTED_SERIES_TEMPLATE =
      TEMPLATE_ROOT + "promql_expectedSeries.mustache";
  private static final String QUERY = "{__name__=\"count\"}";

  private Context context;

  static boolean isWindows() {
    return System.getProperty("os.name").toLowerCase().startsWith("win");
  }

  @BeforeEach
  public void setUp() {
    context = new Context("testingId", "us-east-1", false, false);
    context.setServiceName("serviceName");
  }

  /** A matching series whose scalar datapoint is > 0 passes validation. */
  @Test
  public void testValidationSucceedScalarValueAboveZero() throws Exception {
    String response =
        "{\"status\":\"success\",\"data\":{\"resultType\":\"vector\",\"result\":["
            + "{\"metric\":{\"Telemetry.Source\":\"ServiceEvents\",\"__name__\":\"count\","
            + "\"operation\":\"GET mysql\"},\"value\":[1700000000,\"3\"]}]}}";
    validate(buildValidator(response));
  }

  /** A matching series whose scalar datapoint is exactly 0 fails the {@code >0} assertion. */
  @Test
  public void testValidationFailsWhenValueIsZero() throws Exception {
    String response =
        "{\"status\":\"success\",\"data\":{\"resultType\":\"vector\",\"result\":["
            + "{\"metric\":{\"Telemetry.Source\":\"ServiceEvents\",\"__name__\":\"count\","
            + "\"operation\":\"GET mysql\"},\"value\":[1700000000,\"0\"]}]}}";
    BaseException be = assertThrows(BaseException.class, () -> validate(buildValidator(response)));
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  /** Labels exposed under the {@code @datapoint.} prefix still match the bare template key. */
  @Test
  public void testValidationSucceedWithDatapointPrefixedLabel() throws Exception {
    String response =
        "{\"status\":\"success\",\"data\":{\"resultType\":\"vector\",\"result\":["
            + "{\"metric\":{\"Telemetry.Source\":\"ServiceEvents\",\"__name__\":\"count\","
            + "\"@datapoint.operation\":\"GET mysql\"},\"value\":[1700000000,\"7\"]}]}}";
    validate(buildValidator(response));
  }

  /** When no returned series matches the expected labels, validation throws. */
  @Test
  public void testValidationFailsWhenNoSeriesMatches() throws Exception {
    String response =
        "{\"status\":\"success\",\"data\":{\"resultType\":\"vector\",\"result\":["
            + "{\"metric\":{\"Telemetry.Source\":\"ServiceEvents\",\"__name__\":\"count\","
            + "\"operation\":\"GET other\"},\"value\":[1700000000,\"9\"]}]}}";
    assertThrows(BaseException.class, () -> validate(buildValidator(response)));
  }

  /** An empty result set throws so RetryHelper keeps polling until the metric appears. */
  @Test
  public void testValidationFailsWhenResultEmpty() throws Exception {
    String response = "{\"status\":\"success\",\"data\":{\"resultType\":\"vector\",\"result\":[]}}";
    assertThrows(BaseException.class, () -> validate(buildValidator(response)));
  }

  /** Histogram series have no scalar value; the assertion reads {@code histogram[1].count}. */
  @Test
  public void testSeriesValueSatisfiedFromHistogramCount() throws Exception {
    PromQLValidator validator = new PromQLValidator(mock(PromQLService.class));
    JsonNode series =
        OBJECT_MAPPER.readTree(
            "{\"metric\":{},\"histogram\":[1700000000,{\"count\":\"4\",\"sum\":\"12.5\"}]}");
    assertTrue(validator.seriesValueSatisfies(series, ">0"));
    assertFalse(validator.seriesValueSatisfies(series, ">10"));
  }

  /** A null assertion (no {@code __value__} in the template) is always satisfied. */
  @Test
  public void testSeriesValueSatisfiedWhenAssertionNull() throws Exception {
    PromQLValidator validator = new PromQLValidator(mock(PromQLService.class));
    JsonNode series = OBJECT_MAPPER.readTree("{\"metric\":{},\"value\":[1700000000,\"0\"]}");
    assertTrue(validator.seriesValueSatisfies(series, null));
  }

  /** Each comparison operator is honoured. */
  @Test
  public void testSeriesValueSatisfiedOperators() throws Exception {
    PromQLValidator validator = new PromQLValidator(mock(PromQLService.class));
    JsonNode series = OBJECT_MAPPER.readTree("{\"metric\":{},\"value\":[1700000000,\"5\"]}");
    assertTrue(validator.seriesValueSatisfies(series, ">=5"));
    assertTrue(validator.seriesValueSatisfies(series, "<=5"));
    assertTrue(validator.seriesValueSatisfies(series, "==5"));
    assertTrue(validator.seriesValueSatisfies(series, "<10"));
    assertFalse(validator.seriesValueSatisfies(series, ">5"));
    assertFalse(validator.seriesValueSatisfies(series, "<5"));
  }

  /** A malformed {@code __value__} assertion is a configuration error and throws. */
  @Test
  public void testSeriesValueAssertionUnparseable() {
    PromQLValidator validator = new PromQLValidator(mock(PromQLService.class));
    assertThrows(
        BaseException.class,
        () -> {
          JsonNode series = OBJECT_MAPPER.readTree("{\"metric\":{},\"value\":[1700000000,\"5\"]}");
          validator.seriesValueSatisfies(series, "notAComparison");
        });
  }

  private PromQLValidator buildValidator(String cannedResponse) throws Exception {
    PromQLService promQLService = mock(PromQLService.class);
    when(promQLService.query(any())).thenReturn(OBJECT_MAPPER.readTree(cannedResponse));

    ValidationConfig validationConfig = new ValidationConfig();
    validationConfig.setPromQlQuery(QUERY);

    PromQLValidator validator = new PromQLValidator(promQLService);
    validator.init(
        context, validationConfig, new LocalPathExpectedTemplate(EXPECTED_SERIES_TEMPLATE));
    validator.setMaxRetryCount(1);
    return validator;
  }

  private void validate(PromQLValidator validator) throws Exception {
    validator.validate();
  }
}
