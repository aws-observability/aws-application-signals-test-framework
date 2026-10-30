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
    verify(service, org.mockito.Mockito.atLeastOnce())
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
      "operation-attribution", "rotation-windows", "cpu-profile", "cpu-operation-label",
      "cpu-no-thread-state", "unsampled-operation-label", "identity", "cpu-identity",
      "unsampled-identity", "none-wall-profile", "none-operation-attribution", "thread-count",
      "hotspots", "cpu-hotspots", "data-integrity", "cpu-data-integrity",
      "unsampled-data-integrity", "none-data-integrity", "trace-correlation",
      "unsampled-no-trace-link"
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
      ProfileValidator.ExpectedProfile expected = ProfileValidator.parseExpected(rendered);
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

  /** With no samples of the type yet, an absent-label check waits rather than passing. */
  @Test
  public void testAbsentLabelWaitsForData() throws Exception {
    stub(TYPES, LABEL_NAMES, OPERATION_VALUES, STATE_VALUES,
        "{\"flamegraph\":{\"names\":[],\"total\":\"0\"}}");
    BaseException be =
        assertThrows(
            BaseException.class,
            () -> buildValidator(TEMPLATE_ROOT + "profile_absent.mustache").validate());
    assertEquals(ExceptionCode.EXPECTED_METRIC_NOT_FOUND.getCode(), be.getCode());
  }

  /**
   * Label values are confirmed with a stacktraces query for the resolved profile type and that
   * exact value, since CloudWatch's LabelValues ignores the profile type.
   */
  @Test
  public void testLabelValuesAreConfirmedOnTheProfileType() throws Exception {
    buildValidator().validate();
    verify(service)
        .selectMergeStacktraces(
            eq(WALL_TYPE_ID),
            eq("{@resource.service.name=\"serviceName\",@sample.operation=\"GET /health\"}"),
            anyLong(),
            anyLong());
  }

  /**
   * A value the service has (LabelValues lists it) but no sample of the checked profile type
   * carries does not satisfy the check — the scoping bug LabelValues alone would hide.
   */
  @Test
  public void testLabelValueOnlyOnAnotherProfileTypeFails() throws Exception {
    // Both operation values are listed service-wide, but no wall sample carries either.
    stubStacktraces(sel -> sel.contains("@sample.operation=\"") ? EMPTY : FLAMEGRAPH);
    assertCode(ExceptionCode.DATA_MODEL_NOT_MATCHED);
  }

  /** A label the service has but the profile type's samples lack is not "present". */
  @Test
  public void testLabelNameOnlyOnAnotherProfileTypeFails() throws Exception {
    stubStacktraces(sel -> sel.contains("thread_state=~") ? EMPTY : FLAMEGRAPH);
    assertCode(ExceptionCode.DATA_MODEL_NOT_MATCHED);
  }

  /** An absent label the service has, but not on this profile type's samples, passes. */
  @Test
  public void testAbsentLabelOnlyOnAnotherProfileTypePasses() throws Exception {
    stubStacktraces(sel -> sel.contains("thread_state=~") ? EMPTY : FLAMEGRAPH);
    buildValidator(TEMPLATE_ROOT + "profile_absent.mustache").validate();
  }

  @Test
  public void testWithMatcher() {
    assertEquals("{a=\"b\",c=\"d\"}", ProfileValidator.withMatcher("{a=\"b\"}", "c", "d"));
    assertEquals("{c=\"d\"}", ProfileValidator.withMatcher("{}", "c", "d"));
    assertEquals(
        "{a=\"b\",c=\"x\\\"y\\\\z\"}", ProfileValidator.withMatcher("{a=\"b\"}", "c", "x\"y\\z"));
    assertThrows(IllegalArgumentException.class, () -> ProfileValidator.withMatcher("a", "c", "d"));
  }

  /** With a list of regexes, every one must match some value. */
  @Test
  public void testLabelValuesListRequiresEveryRegex() throws Exception {
    buildValidator(TEMPLATE_ROOT + "profile_values_list.mustache").validate();

    stub(TYPES, LABEL_NAMES, "{\"names\":[\"GET /health\"]}", STATE_VALUES, FLAMEGRAPH);
    BaseException be =
        assertThrows(
            BaseException.class,
            () -> buildValidator(TEMPLATE_ROOT + "profile_values_list.mustache").validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  /** A forbidden frame name (library baked into a native frame) fails the check. */
  @Test
  public void testAbsentFunctionFailsWhenPresent() throws Exception {
    buildValidator(TEMPLATE_ROOT + "profile_absent_functions.mustache").validate();

    stub(TYPES, LABEL_NAMES, OPERATION_VALUES, STATE_VALUES,
        "{\"flamegraph\":{\"names\":[\"total\",\"java.lang.Thread.run\","
            + "\"libc.so.6.start_thread\"],\"total\":\"42\"}}");
    BaseException be =
        assertThrows(
            BaseException.class,
            () -> buildValidator(TEMPLATE_ROOT + "profile_absent_functions.mustache").validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  /** Absent frames are not checked on an empty flame graph: the check waits for data. */
  @Test
  public void testAbsentFunctionsWaitForData() throws Exception {
    stub(TYPES, LABEL_NAMES, OPERATION_VALUES, STATE_VALUES,
        "{\"flamegraph\":{\"names\":[\"total\"],\"total\":\"0\"}}");
    String template = TEMPLATE_ROOT + "profile_absent_functions_only.mustache";
    BaseException be = assertThrows(BaseException.class, () -> buildValidator(template).validate());
    assertEquals(ExceptionCode.EXPECTED_METRIC_NOT_FOUND.getCode(), be.getCode());
  }

  private static final String SDK_SELECTOR =
      "{@resource.service.name=\"serviceName\",@sample.operation=\"GET /aws-sdk-call\"}";
  private static final String HTTP_SELECTOR =
      "{@resource.service.name=\"serviceName\",@sample.operation=\"GET /outgoing-http-call\"}";

  private static String graph(String... frames) {
    StringBuilder names = new StringBuilder("\"total\"");
    for (String f : frames) {
      names.append(",\"").append(f).append('"');
    }
    return "{\"flamegraph\":{\"names\":[" + names + "],\"total\":\"42\"}}";
  }

  private void stubOperationGraph(String selector, String json) throws Exception {
    when(service.selectMergeStacktraces(anyString(), eq(selector), anyLong(), anyLong()))
        .thenReturn(OBJECT_MAPPER.readTree(json));
  }

  /** Each operation's samples hold its own handler and not the other route's handler. */
  @Test
  public void testOperationAttributionSucceeds() throws Exception {
    stubOperationGraph(SDK_SELECTOR, graph("java.lang.Thread.run", "c.F.awssdkCall"));
    stubOperationGraph(HTTP_SELECTOR, graph("java.lang.Thread.run", "c.F.httpCall"));
    buildValidator(TEMPLATE_ROOT + "profile_operations.mustache").validate();
  }

  /** Samples of one route containing the other route's handler are misattributed. */
  @Test
  public void testOperationAttributionFailsOnMisattribution() throws Exception {
    stubOperationGraph(SDK_SELECTOR, graph("c.F.awssdkCall", "c.F.httpCall"));
    stubOperationGraph(HTTP_SELECTOR, graph("c.F.httpCall"));
    BaseException be =
        assertThrows(
            BaseException.class,
            () -> buildValidator(TEMPLATE_ROOT + "profile_operations.mustache").validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  /** A route whose samples lack its handler frame fails. */
  @Test
  public void testOperationAttributionFailsWhenHandlerMissing() throws Exception {
    stubOperationGraph(SDK_SELECTOR, graph("c.F.awssdkCall"));
    stubOperationGraph(HTTP_SELECTOR, graph("java.lang.Thread.run"));
    BaseException be =
        assertThrows(
            BaseException.class,
            () -> buildValidator(TEMPLATE_ROOT + "profile_operations.mustache").validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  /** No operation label on the profile type: attribution cannot pass. */
  @Test
  public void testOperationAttributionFailsWithoutOperationLabel() throws Exception {
    stub(TYPES, "{\"names\":[\"service_name\",\"thread_state\"]}",
        OPERATION_VALUES, STATE_VALUES, FLAMEGRAPH);
    BaseException be =
        assertThrows(
            BaseException.class,
            () -> buildValidator(TEMPLATE_ROOT + "profile_operations.mustache").validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  // CloudWatch Profiles renders Java frames with the source file and line appended.
  private static final String CW_SDK_HANDLER =
      "com.amazon.sampleapp.FrontendServiceController.awssdkCall FrontendServiceController.java:94";
  private static final String CW_HTTP_HANDLER =
      "com.amazon.sampleapp.FrontendServiceController.httpCall FrontendServiceController.java:113";
  private static final String BOTH_ROUTES =
      "{\"names\":[\"GET /\",\"GET /aws-sdk-call\",\"GET /outgoing-http-call\"]}";

  /** The shipped attribution templates match handler frames as CloudWatch names them. */
  @Test
  public void testShippedAttributionMatchesCloudWatchFrameNames() throws Exception {
    stub(TYPES, LABEL_NAMES, BOTH_ROUTES, STATE_VALUES, FLAMEGRAPH);
    stubNoUnexpectedOperations();
    stubOperationGraph(SDK_SELECTOR, graph("java.lang.Thread.run", CW_SDK_HANDLER));
    stubOperationGraph(HTTP_SELECTOR, graph("java.lang.Thread.run", CW_HTTP_HANDLER));
    buildShippedValidator("operation-attribution").validate();
    buildShippedValidator("unsampled-operation-label").validate();
  }

  /** The shipped attribution templates still catch the other route's handler with the suffix. */
  @Test
  public void testShippedAttributionRejectsOtherHandlerWithCloudWatchSuffix() throws Exception {
    stub(TYPES, LABEL_NAMES, BOTH_ROUTES, STATE_VALUES, FLAMEGRAPH);
    stubNoUnexpectedOperations();
    stubOperationGraph(SDK_SELECTOR, graph(CW_SDK_HANDLER, CW_HTTP_HANDLER));
    stubOperationGraph(HTTP_SELECTOR, graph(CW_HTTP_HANDLER));
    BaseException be =
        assertThrows(
            BaseException.class, () -> buildShippedValidator("operation-attribution").validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
    // unsampled-operation-label has the same assertions but is reportOnly: it reports, not fails.
    buildShippedValidator("unsampled-operation-label").validate();
  }

  /** A method whose name only starts with the handler's name is not the handler. */
  @Test
  public void testShippedAttributionDoesNotMatchHandlerNamePrefix() throws Exception {
    stub(TYPES, LABEL_NAMES, BOTH_ROUTES, STATE_VALUES, FLAMEGRAPH);
    stubOperationGraph(SDK_SELECTOR,
        graph("com.amazon.sampleapp.FrontendServiceController.awssdkCallHelper F.java:1"));
    stubOperationGraph(HTTP_SELECTOR, graph(CW_HTTP_HANDLER));
    BaseException be =
        assertThrows(
            BaseException.class, () -> buildShippedValidator("operation-attribution").validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  /** The shipped rotation check reads 5-minute buckets, the resolution CloudWatch returns. */
  @Test
  public void testShippedRotationWindowsUsesFiveMinuteBuckets() throws Exception {
    when(service.selectSeries(anyString(), anyString(), anyLong(), anyLong(), org.mockito.ArgumentMatchers.anyDouble()))
        .thenReturn(OBJECT_MAPPER.readTree(series(300_000, 600_000, 900_000)));
    buildShippedValidator("rotation-windows").validate();
    verify(service)
        .selectSeries(eq(WALL_TYPE_ID), anyString(), anyLong(), anyLong(), eq(300.0));
  }

  /**
   * Two 5-minute buckets are not enough, but the shipped rotation check is reportOnly, so it
   * reports instead of failing. (The enforced logic is covered by testWindowsFailWithGap.)
   */
  @Test
  public void testShippedRotationWindowsReportsTwoBuckets() throws Exception {
    when(service.selectSeries(anyString(), anyString(), anyLong(), anyLong(), org.mockito.ArgumentMatchers.anyDouble()))
        .thenReturn(OBJECT_MAPPER.readTree(series(300_000, 600_000)));
    buildShippedValidator("rotation-windows").validate();
  }

  /** A validator built from a shipped java/ec2/profiler validation YAML and its template. */
  private ProfileValidator buildShippedValidator(String name) throws Exception {
    ValidationConfig config =
        new com.amazon.aoc.helpers.ConfigLoadHelper()
            .loadConfigFromFile("java/ec2/profiler/" + name + "-validation.yml")
            .get(0);
    ProfileValidator validator = new ProfileValidator(service);
    validator.init(context, config, config.getExpectedProfileTemplate());
    validator.setMaxRetryCount(1);
    return validator;
  }

  // ---- identity checks: exactLabelValues, labelValueCounts, allLabelValuesMatch ----

  private static final String EMPTY = "{\"flamegraph\":{\"names\":[],\"total\":\"0\"}}";
  private static final String IDENTITY_LABELS =
      "{\"names\":[\"service_name\",\"@sample.operation\",\"@sample.thread.name\","
          + "\"@resource.process.pid\",\"@resource.service.instance.id\"]}";

  /** Stub the stacktraces query per selector (any profile type). */
  private void stubStacktraces(java.util.function.Function<String, String> bySelector)
      throws Exception {
    when(service.selectMergeStacktraces(anyString(), anyString(), anyLong(), anyLong()))
        .thenAnswer(
            inv -> OBJECT_MAPPER.readTree(bySelector.apply(inv.getArgument(1, String.class))));
  }

  private void stubIdentity(String pids, String instanceIds) throws Exception {
    when(service.labelNames(anyString(), anyLong(), anyLong()))
        .thenReturn(OBJECT_MAPPER.readTree(IDENTITY_LABELS));
    when(service.labelValues(eq("@resource.process.pid"), anyString(), anyLong(), anyLong()))
        .thenReturn(OBJECT_MAPPER.readTree("{\"names\":" + pids + "}"));
    when(service.labelValues(eq("@resource.service.instance.id"), anyString(), anyLong(), anyLong()))
        .thenReturn(OBJECT_MAPPER.readTree("{\"names\":" + instanceIds + "}"));
  }

  private ProfileValidator buildIdentityValidator(String pid) throws Exception {
    java.util.Map<String, String> profileContext = new java.util.HashMap<>();
    profileContext.put("pid", pid);
    context.setProfileContext(profileContext);
    return buildValidator(TEMPLATE_ROOT + "profile_identity.mustache");
  }

  /** The service's samples carry exactly its own PID and one instance id; request threads only. */
  @Test
  public void testIdentitySucceeds() throws Exception {
    stubIdentity("[\"1234\"]", "[\"i-1\"]");
    stubStacktraces(sel -> sel.contains("!~") ? EMPTY : FLAMEGRAPH);
    buildIdentityValidator("1234").validate();
    verify(service)
        .selectMergeStacktraces(
            eq(WALL_TYPE_ID),
            eq("{@resource.service.name=\"serviceName\",@sample.operation=\"GET /a\","
                + "@sample.thread.name!~\"http-nio-8080-exec-[0-9]+\"}"),
            anyLong(),
            anyLong());
  }

  /** Samples of another process (a second PID) under the service fail the exact-PID check. */
  @Test
  public void testIdentityFailsOnForeignPid() throws Exception {
    stubIdentity("[\"1234\",\"999\"]", "[\"i-1\"]");
    stubStacktraces(sel -> sel.contains("!~") ? EMPTY : FLAMEGRAPH);
    BaseException be =
        assertThrows(BaseException.class, () -> buildIdentityValidator("1234").validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  /** A PID only listed service-wide but on no sample of the type is not counted. */
  @Test
  public void testIdentityIgnoresPidWithoutSamplesOfTheType() throws Exception {
    stubIdentity("[\"1234\",\"999\"]", "[\"i-1\"]");
    stubStacktraces(
        sel -> sel.contains("!~") || sel.contains("process.pid=\"999\"") ? EMPTY : FLAMEGRAPH);
    buildIdentityValidator("1234").validate();
  }

  /** Two service.instance.id values (samples from two agent instances) fail the count check. */
  @Test
  public void testIdentityFailsOnTwoInstanceIds() throws Exception {
    stubIdentity("[\"1234\"]", "[\"i-1\",\"i-2\"]");
    stubStacktraces(sel -> sel.contains("!~") ? EMPTY : FLAMEGRAPH);
    BaseException be =
        assertThrows(BaseException.class, () -> buildIdentityValidator("1234").validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  /** A request sample on a non-request thread fails allLabelValuesMatch. */
  @Test
  public void testIdentityFailsWhenRequestSampleOnOtherThread() throws Exception {
    stubIdentity("[\"1234\"]", "[\"i-1\"]");
    stubStacktraces(sel -> FLAMEGRAPH);
    BaseException be =
        assertThrows(BaseException.class, () -> buildIdentityValidator("1234").validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  /** A missing deploy-time value (no --profile-context) fails instead of matching nothing. */
  @Test
  public void testIdentityFailsWithoutProfileContext() throws Exception {
    stubIdentity("[\"1234\"]", "[\"i-1\"]");
    stubStacktraces(sel -> sel.contains("!~") ? EMPTY : FLAMEGRAPH);
    context.setProfileContext(null);
    BaseException be =
        assertThrows(
            BaseException.class,
            () -> buildValidator(TEMPLATE_ROOT + "profile_identity.mustache").validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  @Test
  public void testWithMatcherOperators() {
    assertEquals("{a=\"b\",c=~\".+\"}", ProfileValidator.withMatcher("{a=\"b\"}", "c", "=~", ".+"));
    assertEquals("{a=\"b\",c!~\"x\"}", ProfileValidator.withMatcher("{a=\"b\"}", "c", "!~", "x"));
  }

  // ---- thread count, allowed operations, hot spots, data integrity ----

  /** The allowedLabelValues query (any operation outside the allowed list) finds no samples. */
  private void stubNoUnexpectedOperations() throws Exception {
    when(service.selectMergeStacktraces(
            anyString(), org.mockito.ArgumentMatchers.contains("!~"), anyLong(), anyLong()))
        .thenReturn(OBJECT_MAPPER.readTree(EMPTY));
  }

  /**
   * A flame graph with the given total whose level-1 nodes are {@code frames} (name, total pairs),
   * in Pyroscope's flamebearer shape: per level, groups of offset, total, self, name index.
   */
  private static String levelsGraph(long total, Object... frames) {
    StringBuilder names = new StringBuilder("\"total\"");
    StringBuilder level1 = new StringBuilder();
    for (int i = 0; i < frames.length; i += 2) {
      names.append(",\"").append(frames[i]).append('"');
      if (level1.length() > 0) {
        level1.append(',');
      }
      level1.append("0,").append(frames[i + 1]).append(",0,").append(i / 2 + 1);
    }
    return "{\"flamegraph\":{\"names\":[" + names + "],\"total\":\"" + total + "\","
        + "\"levels\":[{\"values\":[0," + total + ",0,0]},{\"values\":[" + level1 + "]}]}}";
  }

  private static final String THREAD_LABELS =
      "{\"names\":[\"service_name\",\"@sample.operation\",\"@sample.thread.name\"]}";

  private void stubThreads(String threadNames) throws Exception {
    when(service.labelNames(anyString(), anyLong(), anyLong()))
        .thenReturn(OBJECT_MAPPER.readTree(THREAD_LABELS));
    when(service.labelValues(eq("@sample.thread.name"), anyString(), anyLong(), anyLong()))
        .thenReturn(OBJECT_MAPPER.readTree("{\"names\":" + threadNames + "}"));
  }

  private ProfileValidator buildContextValidator(String template, String... keyValues)
      throws Exception {
    java.util.Map<String, String> profileContext = new java.util.HashMap<>();
    for (int i = 0; i < keyValues.length; i += 2) {
      profileContext.put(keyValues[i], keyValues[i + 1]);
    }
    context.setProfileContext(profileContext);
    return buildValidator(TEMPLATE_ROOT + template);
  }

  /** Enough distinct thread names on the wall samples passes. */
  @Test
  public void testMinLabelValueCountsSucceeds() throws Exception {
    stubThreads("[\"t1\",\"t2\",\"t3\"]");
    stubStacktraces(sel -> FLAMEGRAPH);
    buildContextValidator("profile_min_values.mustache", "minThreads", "3").validate();
  }

  /** Threads listed service-wide but without wall samples do not count towards the minimum. */
  @Test
  public void testMinLabelValueCountsFailsWhenThreadsAreMissing() throws Exception {
    stubThreads("[\"t1\",\"t2\",\"t3\"]");
    stubStacktraces(sel -> sel.contains("thread.name=\"t3\"") ? EMPTY : FLAMEGRAPH);
    BaseException be =
        assertThrows(
            BaseException.class,
            () -> buildContextValidator("profile_min_values.mustache", "minThreads", "3").validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  /** A missing deploy-time minimum fails instead of passing trivially. */
  @Test
  public void testMinLabelValueCountsFailsWithoutContext() throws Exception {
    stubThreads("[\"t1\"]");
    stubStacktraces(sel -> FLAMEGRAPH);
    BaseException be =
        assertThrows(
            BaseException.class,
            () -> buildContextValidator("profile_min_values.mustache").validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  /** No sample carries an operation outside the allowed list: passes, with the query sent. */
  @Test
  public void testAllowedLabelValuesSucceeds() throws Exception {
    stubStacktraces(sel -> sel.contains("!~") ? EMPTY : FLAMEGRAPH);
    buildValidator(TEMPLATE_ROOT + "profile_allowed_values.mustache").validate();
    verify(service)
        .selectMergeStacktraces(
            eq(WALL_TYPE_ID),
            eq("{@resource.service.name=\"serviceName\",@sample.operation=~\".+\","
                + "@sample.operation!~\"(GET /health|GET /aws-sdk-call)\"}"),
            anyLong(),
            anyLong());
  }

  /** An unexpected operation (here any sample outside the list) fails. */
  @Test
  public void testAllowedLabelValuesFailsOnUnexpectedOperation() throws Exception {
    stubStacktraces(sel -> FLAMEGRAPH);
    BaseException be =
        assertThrows(
            BaseException.class,
            () -> buildValidator(TEMPLATE_ROOT + "profile_allowed_values.mustache").validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  /** frameTime sums the totals of every node whose name matches, across levels. */
  @Test
  public void testFrameTimeSumsMatchingNodes() throws Exception {
    String json = levelsGraph(100, "a.Handler.run A.java:1", 60, "a.Handler.run A.java:2", 25, "b.Other.x", 15);
    assertEquals(
        85,
        ProfileValidator.frameTime(
            OBJECT_MAPPER.readTree(json).path("flamegraph"), "^a\\.Handler\\.run( |$)"));
  }

  /** A handler holding at least its minimum share of its operation's samples passes. */
  @Test
  public void testHotspotsSucceed() throws Exception {
    stubStacktraces(
        sel -> levelsGraph(100, "c.F.awssdkCall F.java:9", 90, "java.lang.Thread.run", 10));
    buildValidator(TEMPLATE_ROOT + "profile_hotspots.mustache").validate();
  }

  /** A handler that no longer dominates its operation's samples fails. */
  @Test
  public void testHotspotsFailWhenShareDrops() throws Exception {
    stubStacktraces(
        sel -> levelsGraph(100, "c.F.awssdkCall F.java:9", 40, "java.lang.Thread.run", 60));
    BaseException be =
        assertThrows(
            BaseException.class,
            () -> buildValidator(TEMPLATE_ROOT + "profile_hotspots.mustache").validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  /** The backend total matching what the agent exported passes, queried over that exact window. */
  @Test
  public void testExpectedTotalSucceedsOverExactWindow() throws Exception {
    stubStacktraces(sel -> levelsGraph(1_000_000, "x", 1_000_000));
    buildContextValidator(
            "profile_expected_total.mustache",
            "expectedNanos", "1010000", "startMs", "1000", "endMs", "61000")
        .validate();
    verify(service, org.mockito.Mockito.atLeastOnce())
        .selectMergeStacktraces(eq(WALL_TYPE_ID), anyString(), eq(1000L), eq(61000L));
  }

  /** Less than was exported means data is missing (or still ingesting): wait, then fail. */
  @Test
  public void testExpectedTotalWaitsWhenDataIsMissing() throws Exception {
    stubStacktraces(sel -> levelsGraph(900_000, "x", 900_000));
    BaseException be =
        assertThrows(
            BaseException.class,
            () ->
                buildContextValidator(
                        "profile_expected_total.mustache",
                        "expectedNanos", "1000000", "startMs", "1000", "endMs", "61000")
                    .validate());
    assertEquals(ExceptionCode.EXPECTED_METRIC_NOT_FOUND.getCode(), be.getCode());
  }

  /** More than was exported cannot be explained by what was sent: fail. */
  @Test
  public void testExpectedTotalFailsWhenMoreThanSent() throws Exception {
    stubStacktraces(sel -> levelsGraph(1_100_000, "x", 1_100_000));
    BaseException be =
        assertThrows(
            BaseException.class,
            () ->
                buildContextValidator(
                        "profile_expected_total.mustache",
                        "expectedNanos", "1000000", "startMs", "1000", "endMs", "61000")
                    .validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  /**
   * reportOnly: the check runs, but a total far outside the tolerance passes (reported), and so
   * does a check with no data at all after its short retry budget.
   */
  @Test
  public void testReportOnlyCheckReportsInsteadOfFailing() throws Exception {
    stubStacktraces(sel -> levelsGraph(500_000, "x", 500_000));
    buildContextValidator(
            "profile_expected_total_report_only.mustache",
            "expectedNanos", "1000000", "startMs", "1000", "endMs", "61000")
        .validate();
    stubStacktraces(sel -> EMPTY);
    buildContextValidator(
            "profile_expected_total_report_only.mustache",
            "expectedNanos", "1000000", "startMs", "1000", "endMs", "61000")
        .validate();
    verify(service, org.mockito.Mockito.atLeastOnce())
        .selectMergeStacktraces(eq(WALL_TYPE_ID), anyString(), eq(1000L), eq(61000L));
  }

  // Trace IDs of requests made at deploy, as recorded in the deploy-time context.
  private static final String SDK_TRACE_1 = "5759e988bd862e3fe1be46a994272793";
  private static final String SDK_TRACE_2 = "5759e988bd862e3fe1be46a994272794";
  private static final String HTTP_TRACE_1 = "6a2b9c01aa0000000000000000000001";
  private static final String HTTP_TRACE_2 = "6a2b9c01aa0000000000000000000002";
  private static final String UNSAMPLED_SDK_TRACE = "7b3c0d12bb0000000000000000000001";
  private static final String UNSAMPLED_HTTP_TRACE = "7b3c0d12bb0000000000000000000002";

  private ProfileValidator shippedValidator(
      com.amazon.aoc.fileconfigs.PredefinedExpectedTemplate template, String... keyValues)
      throws Exception {
    java.util.Map<String, String> profileContext = new java.util.HashMap<>();
    for (int i = 0; i < keyValues.length; i += 2) {
      profileContext.put(keyValues[i], keyValues[i + 1]);
    }
    context.setProfileContext(profileContext);
    ProfileValidator validator = new ProfileValidator(service);
    validator.init(context, new ValidationConfig(), template);
    validator.setMaxRetryCount(1);
    return validator;
  }

  private ProfileValidator traceCorrelationValidator() throws Exception {
    return shippedValidator(
        com.amazon.aoc.fileconfigs.PredefinedExpectedTemplate.JAVA_EC2_PROFILER_TRACE_CORRELATION,
        "mainSdkTraceId1", SDK_TRACE_1, "mainSdkTraceId2", SDK_TRACE_2,
        "mainHttpTraceId1", HTTP_TRACE_1, "mainHttpTraceId2", HTTP_TRACE_2);
  }

  private ProfileValidator unlinkedValidator() throws Exception {
    return shippedValidator(
        com.amazon.aoc.fileconfigs.PredefinedExpectedTemplate
            .JAVA_EC2_PROFILER_UNSAMPLED_NO_TRACE_LINK,
        "unsampledSdkTraceId1", UNSAMPLED_SDK_TRACE, "unsampledHttpTraceId1", UNSAMPLED_HTTP_TRACE);
  }

  private static String traceMatcher(String traceId) {
    return "__trace_id__=\"" + traceId + "\"";
  }

  /** Each request's trace ID selects samples holding its own handler and not the other route's. */
  @Test
  public void testTraceCorrelationSucceeds() throws Exception {
    stubStacktraces(
        sel ->
            sel.contains(traceMatcher(SDK_TRACE_1)) || sel.contains(traceMatcher(SDK_TRACE_2))
                ? graph("java.lang.Thread.run", CW_SDK_HANDLER)
                : sel.contains(traceMatcher(HTTP_TRACE_1)) || sel.contains(traceMatcher(HTTP_TRACE_2))
                    ? graph("java.lang.Thread.run", CW_HTTP_HANDLER)
                    : EMPTY);
    traceCorrelationValidator().validate();
    for (String traceId : new String[] {SDK_TRACE_1, SDK_TRACE_2, HTTP_TRACE_1, HTTP_TRACE_2}) {
      verify(service)
          .selectMergeStacktraces(
              eq(WALL_TYPE_ID),
              eq("{@resource.service.name=\"serviceName\"," + traceMatcher(traceId) + "}"),
              anyLong(),
              anyLong());
    }
  }

  /** A trace whose samples hold the other route's handler is linked to the wrong request. */
  @Test
  public void testTraceCorrelationFailsWhenTraceHoldsOtherHandler() throws Exception {
    stubStacktraces(
        sel ->
            sel.contains(traceMatcher(HTTP_TRACE_2))
                ? graph(CW_HTTP_HANDLER, CW_SDK_HANDLER)
                : sel.contains(traceMatcher(HTTP_TRACE_1))
                    ? graph(CW_HTTP_HANDLER)
                    : graph(CW_SDK_HANDLER));
    BaseException be = assertThrows(BaseException.class, () -> traceCorrelationValidator().validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  /** A request whose trace links to no samples (yet) does not pass. */
  @Test
  public void testTraceCorrelationWaitsForLinkedSamples() throws Exception {
    stubStacktraces(sel -> sel.contains(traceMatcher(SDK_TRACE_2)) ? EMPTY : graph(CW_SDK_HANDLER));
    BaseException be = assertThrows(BaseException.class, () -> traceCorrelationValidator().validate());
    assertEquals(ExceptionCode.EXPECTED_METRIC_NOT_FOUND.getCode(), be.getCode());
  }

  /**
   * A trace ID missing from the context (the request at deploy failed) or all zeros (no active span)
   * fails before any query: an empty matcher would select every sample.
   */
  @Test
  public void testTraceCorrelationRejectsInvalidTraceIds() throws Exception {
    assertThrows(
        IllegalArgumentException.class,
        () ->
            shippedValidator(
                    com.amazon.aoc.fileconfigs.PredefinedExpectedTemplate
                        .JAVA_EC2_PROFILER_TRACE_CORRELATION,
                    "mainSdkTraceId1", SDK_TRACE_1)
                .validate());
    assertThrows(
        IllegalArgumentException.class,
        () ->
            shippedValidator(
                    com.amazon.aoc.fileconfigs.PredefinedExpectedTemplate
                        .JAVA_EC2_PROFILER_UNSAMPLED_NO_TRACE_LINK,
                    "unsampledSdkTraceId1", "00000000000000000000000000000000",
                    "unsampledHttpTraceId1", UNSAMPLED_HTTP_TRACE)
                .validate());
    verify(service, org.mockito.Mockito.never()).profileTypes(anyLong(), anyLong());
  }

  private static final String BUSY_SERVICE =
      "{\"flamegraph\":{\"names\":[\"total\",\"java.lang.Thread.run\"],"
          + "\"total\":\"20000000000\"}}";

  /** The unsampled service has samples, but none link to its requests' (dropped) traces. */
  @Test
  public void testUnsampledNoTraceLinkSucceeds() throws Exception {
    stubStacktraces(sel -> sel.contains("__trace_id__") ? EMPTY : BUSY_SERVICE);
    unlinkedValidator().validate();
    verify(service)
        .selectMergeStacktraces(
            eq(WALL_TYPE_ID),
            eq("{@resource.service.name=\"serviceName\"," + traceMatcher(UNSAMPLED_HTTP_TRACE) + "}"),
            anyLong(),
            anyLong());
  }

  /** A sample linking to an unsampled request's trace points at a trace that was never exported. */
  @Test
  public void testUnsampledNoTraceLinkFailsWhenLinked() throws Exception {
    stubStacktraces(
        sel -> sel.contains(traceMatcher(UNSAMPLED_SDK_TRACE)) ? graph(CW_SDK_HANDLER) : BUSY_SERVICE);
    BaseException be = assertThrows(BaseException.class, () -> unlinkedValidator().validate());
    assertEquals(ExceptionCode.DATA_MODEL_NOT_MATCHED.getCode(), be.getCode());
  }

  /** Without data on the unsampled service, "no linked samples" proves nothing: it waits. */
  @Test
  public void testUnsampledNoTraceLinkWaitsForData() throws Exception {
    stubStacktraces(sel -> EMPTY);
    BaseException be = assertThrows(BaseException.class, () -> unlinkedValidator().validate());
    assertEquals(ExceptionCode.EXPECTED_METRIC_NOT_FOUND.getCode(), be.getCode());
  }

  private ProfileValidator.ExpectedProfile shippedExpected(String name) throws Exception {
    ValidationConfig config =
        new com.amazon.aoc.helpers.ConfigLoadHelper()
            .loadConfigFromFile("java/ec2/profiler/" + name + "-validation.yml")
            .get(0);
    return ProfileValidator.parseExpected(
        new com.amazon.aoc.helpers.MustacheHelper()
            .render(config.getExpectedProfileTemplate(), context));
  }

  /**
   * The slow checks are reportOnly with a reason; the wall data integrity ones say an ADOT Java
   * agent change is needed to enforce them. Every other shipped check is enforced.
   */
  @Test
  public void testShippedSlowChecksAreReportOnly() throws Exception {
    java.util.List<String> wall =
        Arrays.asList("data-integrity", "unsampled-data-integrity", "none-data-integrity");
    java.util.List<String> reportOnly =
        Arrays.asList(
            "data-integrity", "unsampled-data-integrity", "none-data-integrity",
            "cpu-data-integrity", "rotation-windows", "unsampled-operation-label");
    for (String name : reportOnly) {
      ProfileValidator.ExpectedProfile expected = shippedExpected(name);
      assertEquals("true", expected.getReportOnly(), name);
      org.junit.jupiter.api.Assertions.assertFalse(expected.getReportOnlyReason().isEmpty(), name);
      if (wall.contains(name)) {
        org.junit.jupiter.api.Assertions.assertTrue(
            expected.getReportOnlyReason().contains("ADOT Java agent change needed"), name);
      }
    }
    for (String name :
        new String[] {
          "operation-attribution", "hotspots", "thread-count", "identity", "trace-correlation",
          "unsampled-no-trace-link"
        }) {
      assertNull(shippedExpected(name).getReportOnly(), name);
    }
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
