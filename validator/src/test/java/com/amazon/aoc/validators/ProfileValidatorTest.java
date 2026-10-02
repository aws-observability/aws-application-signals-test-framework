/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
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
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.amazon.aoc.exception.BaseException;
import com.amazon.aoc.exception.ExceptionCode;
import com.amazon.aoc.fileconfigs.LocalPathExpectedTemplate;
import com.amazon.aoc.models.Context;
import com.amazon.aoc.models.ValidationConfig;
import com.amazon.aoc.services.ProfilesService;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Arrays;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.DisabledIf;

/**
 * Unit tests for {@link ProfileValidator}. The CloudWatch Profiles query calls are mocked, so the
 * tests exercise profile-type resolution, label-name normalization, label-value and flame-graph
 * matching against canned Pyroscope JSON responses. Disabled on Windows because the template is
 * loaded from a {@code file://} path.
 */
@DisabledIf("isWindows")
public class ProfileValidatorTest {
  private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();
  private static final String TEMPLATE =
      "file://" + System.getProperty("user.dir") + "/src/test/test-resources/profile_expected.mustache";
  private static final String WALL_TYPE_ID = "wall:wall:nanoseconds:wall:nanoseconds";

  private static final String TYPES =
      "{\"profileTypes\":[{\"ID\":\"memory:alloc_space:bytes:space:bytes\"},"
          + "{\"ID\":\"" + WALL_TYPE_ID + "\"}]}";
  // Sample attributes exposed prefixed / underscored, to exercise label-name normalization.
  private static final String LABEL_NAMES =
      "{\"names\":[\"service_name\",\"@sample.operation\",\"thread_state\"]}";
  private static final String OPERATION_VALUES = "{\"names\":[\"GET /health\",\"GET /aws-sdk-call\"]}";
  private static final String STATE_VALUES = "{\"names\":[\"RUNNABLE\",\"SLEEPING\"]}";
  private static final String FLAMEGRAPH =
      "{\"flamegraph\":{\"names\":[\"total\",\"java.lang.Thread.run\","
          + "\"com.amazon.sampleapp.FrontendServiceController.awssdkCall\"],\"total\":\"42\"}}";

  private Context context;
  private ProfilesService service;

  static boolean isWindows() {
    return System.getProperty("os.name").toLowerCase().startsWith("win");
  }

  @BeforeEach
  public void setUp() throws Exception {
    context = new Context("testingId", "us-east-1", false, false);
    context.setServiceName("serviceName");
    service = mock(ProfilesService.class);
    stub(TYPES, LABEL_NAMES, OPERATION_VALUES, STATE_VALUES, FLAMEGRAPH);
  }

  /** Every check in the template is satisfied. */
  @Test
  public void testValidationSucceeds() throws Exception {
    buildValidator().validate();
  }

  /** The flame graph is queried with the concrete type ID resolved from ProfileTypes. */
  @Test
  public void testResolvedProfileTypeIdIsUsedForFlameGraph() throws Exception {
    buildValidator().validate();
    verify(service)
        .selectMergeStacktraces(eq(WALL_TYPE_ID), anyString(), anyLong(), anyLong());
  }

  /** No advertised type matches the template's profileType regex. */
  @Test
  public void testFailsWhenProfileTypeMissing() throws Exception {
    stub("{\"profileTypes\":[{\"ID\":\"memory:alloc_space:bytes:space:bytes\"}]}",
        LABEL_NAMES, OPERATION_VALUES, STATE_VALUES, FLAMEGRAPH);
    assertCode(ExceptionCode.EXPECTED_METRIC_NOT_FOUND);
  }

  /** A required label (thread.state) is absent. */
  @Test
  public void testFailsWhenLabelMissing() throws Exception {
    stub(TYPES, "{\"names\":[\"service_name\",\"operation\"]}",
        OPERATION_VALUES, STATE_VALUES, FLAMEGRAPH);
    assertCode(ExceptionCode.DATA_MODEL_NOT_MATCHED);
  }

  /** The label exists but no value matches (operation is not an HTTP route). */
  @Test
  public void testFailsWhenLabelValueDoesNotMatch() throws Exception {
    stub(TYPES, LABEL_NAMES, "{\"names\":[\"UnknownOperation\"]}", STATE_VALUES, FLAMEGRAPH);
    assertCode(ExceptionCode.DATA_MODEL_NOT_MATCHED);
  }

  /** No frame in the flame graph matches the expected application function. */
  @Test
  public void testFailsWhenFunctionMissing() throws Exception {
    stub(TYPES, LABEL_NAMES, OPERATION_VALUES, STATE_VALUES,
        "{\"flamegraph\":{\"names\":[\"total\",\"java.lang.Thread.run\"],\"total\":\"42\"}}");
    assertCode(ExceptionCode.DATA_MODEL_NOT_MATCHED);
  }

  /** The flame graph is empty (total below minTotal). */
  @Test
  public void testFailsWhenFlameGraphEmpty() throws Exception {
    stub(TYPES, LABEL_NAMES, OPERATION_VALUES, STATE_VALUES,
        "{\"flamegraph\":{\"names\":[],\"total\":\"0\"}}");
    assertCode(ExceptionCode.EXPECTED_METRIC_NOT_FOUND);
  }

  /** Label names match across bare, scope-prefixed and underscored spellings. */
  @Test
  public void testFindLabelNormalization() {
    java.util.List<String> names = Arrays.asList("@sample.thread.state", "service_name");
    assertEquals("@sample.thread.state", ProfileValidator.findLabel(names, "thread.state"));
    assertEquals("@sample.thread.state", ProfileValidator.findLabel(names, "thread_state"));
    assertEquals("service_name", ProfileValidator.findLabel(names, "@resource.service.name"));
    assertNull(ProfileValidator.findLabel(names, "operation"));
  }

  /**
   * Every shipped Java EC2 profiler validation YAML loads, is a "profile" validation, and resolves
   * to a template that parses with a profileType — so a typo in a real config fails here, not in a
   * cloud run.
   */
  @Test
  public void testShippedJavaEc2ProfilerConfigsLoad() throws Exception {
    String[] configs = {
      "wall-profile", "operation-label", "thread-state-label",
      "app-stack-frames", "alloc-space-profile", "alloc-objects-profile",
      "rotation-windows", "cpu-profile", "cpu-operation-label",
      "cpu-no-thread-state", "unsampled-operation-label"
    };
    for (String name : configs) {
      java.util.List<ValidationConfig> loaded =
          new com.amazon.aoc.helpers.ConfigLoadHelper()
              .loadConfigFromFile("java/ec2/profiler/" + name + "-validation.yml");
      assertEquals(1, loaded.size(), name);
      ValidationConfig config = loaded.get(0);
      assertEquals("profile", config.getValidationType(), name);
      String rendered =
          new com.amazon.aoc.helpers.MustacheHelper()
              .render(config.getExpectedProfileTemplate(), context);
      ProfileValidator.ExpectedProfile expected =
          OBJECT_MAPPER.readValue(rendered, ProfileValidator.ExpectedProfile.class);
      org.junit.jupiter.api.Assertions.assertNotNull(expected.getProfileType(), name);
    }
  }

  private static final String TEMPLATE_ROOT =
      "file://" + System.getProperty("user.dir") + "/src/test/test-resources/";

  private static String series(long... timestampsWithData) {
    StringBuilder points = new StringBuilder();
    for (long ts : timestampsWithData) {
      if (points.length() > 0) {
        points.append(',');
      }
      points.append("{\"value\":5.0,\"timestamp\":").append(ts).append('}');
    }
    return "{\"series\":[{\"labels\":[],\"points\":[" + points + "]}]}";
  }

  /** Three consecutive 60s windows with data satisfies minWindows=3. */
  @Test
  public void testWindowsSucceedWithThreeConsecutive() throws Exception {
    when(service.selectSeries(anyString(), anyString(), anyLong(), anyLong(), org.mockito.ArgumentMatchers.anyDouble()))
        .thenReturn(OBJECT_MAPPER.readTree(series(60_000, 120_000, 180_000)));
    buildValidator(TEMPLATE_ROOT + "profile_windows.mustache").validate();
  }

  /** A missing window (gap) breaks the run: 2 + 1 windows does not satisfy minWindows=3. */
  @Test
  public void testWindowsFailWithGap() throws Exception {
    when(service.selectSeries(anyString(), anyString(), anyLong(), anyLong(), org.mockito.ArgumentMatchers.anyDouble()))
        .thenReturn(OBJECT_MAPPER.readTree(series(60_000, 120_000, 240_000)));
    BaseException be =
        assertThrows(
            BaseException.class,
            () -> buildValidator(TEMPLATE_ROOT + "profile_windows.mustache").validate());
    assertEquals(ExceptionCode.EXPECTED_METRIC_NOT_FOUND.getCode(), be.getCode());
  }

  /** Zero-valued points do not count as windows with data. */
  @Test
  public void testLongestConsecutiveRunIgnoresZeroValues() throws Exception {
    String json =
        "{\"series\":[{\"points\":[{\"value\":1,\"timestamp\":60000},"
            + "{\"value\":0,\"timestamp\":120000},{\"value\":1,\"timestamp\":180000}]}]}";
    assertEquals(
        1, ProfileValidator.longestConsecutiveRun(OBJECT_MAPPER.readTree(json).path("series"), 60_000));
  }

  /** An absent label that is indeed absent passes. */
  @Test
  public void testAbsentLabelSucceedsWhenAbsent() throws Exception {
    stub(TYPES, "{\"names\":[\"service_name\",\"@sample.operation\"]}",
        OPERATION_VALUES, STATE_VALUES, FLAMEGRAPH);
    buildValidator(TEMPLATE_ROOT + "profile_absent.mustache").validate();
  }

  /** An absent label that is present fails (thread.state appears as thread_state). */
  @Test
  public void testAbsentLabelFailsWhenPresent() throws Exception {
    BaseException be =
        assertThrows(
            BaseException.class,
            () -> buildValidator(TEMPLATE_ROOT + "profile_absent.mustache").validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  /** With no labels at all (no data yet), an absent-label check waits rather than passing. */
  @Test
  public void testAbsentLabelWaitsForData() throws Exception {
    stub(TYPES, "{\"names\":[]}", OPERATION_VALUES, STATE_VALUES, FLAMEGRAPH);
    BaseException be =
        assertThrows(
            BaseException.class,
            () -> buildValidator(TEMPLATE_ROOT + "profile_absent.mustache").validate());
    assertEquals(ExceptionCode.EXPECTED_METRIC_NOT_FOUND.getCode(), be.getCode());
  }

  private ProfileValidator buildValidator(String template) throws Exception {
    ProfileValidator validator = new ProfileValidator(service);
    validator.init(context, new ValidationConfig(), new LocalPathExpectedTemplate(template));
    validator.setMaxRetryCount(1);
    return validator;
  }

  private void stub(String types, String labelNames, String operationValues, String stateValues,
      String flamegraph) throws Exception {
    when(service.profileTypes(anyLong(), anyLong())).thenReturn(OBJECT_MAPPER.readTree(types));
    when(service.labelNames(anyString(), anyLong(), anyLong()))
        .thenReturn(OBJECT_MAPPER.readTree(labelNames));
    when(service.labelValues(eq("@sample.operation"), anyString(), anyLong(), anyLong()))
        .thenReturn(OBJECT_MAPPER.readTree(operationValues));
    when(service.labelValues(eq("operation"), anyString(), anyLong(), anyLong()))
        .thenReturn(OBJECT_MAPPER.readTree(operationValues));
    when(service.labelValues(eq("thread_state"), anyString(), anyLong(), anyLong()))
        .thenReturn(OBJECT_MAPPER.readTree(stateValues));
    when(service.selectMergeStacktraces(anyString(), anyString(), anyLong(), anyLong()))
        .thenReturn(OBJECT_MAPPER.readTree(flamegraph));
  }

  private void assertCode(ExceptionCode code) throws Exception {
    BaseException be = assertThrows(BaseException.class, () -> buildValidator().validate());
    assertEquals(code.getCode(), be.getCode());
  }

  private ProfileValidator buildValidator() throws Exception {
    ProfileValidator validator = new ProfileValidator(service);
    validator.init(context, new ValidationConfig(), new LocalPathExpectedTemplate(TEMPLATE));
    validator.setMaxRetryCount(1);
    return validator;
  }
}
