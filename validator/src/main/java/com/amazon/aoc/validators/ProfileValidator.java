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

import com.amazon.aoc.exception.BaseException;
import com.amazon.aoc.exception.ExceptionCode;
import com.amazon.aoc.fileconfigs.FileConfig;
import com.amazon.aoc.helpers.MustacheHelper;
import com.amazon.aoc.helpers.RetryHelper;
import com.amazon.aoc.models.Context;
import com.amazon.aoc.models.ValidationConfig;
import com.amazon.aoc.services.ProfilesService;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.common.annotations.VisibleForTesting;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Pattern;
import lombok.Data;
import lombok.extern.log4j.Log4j2;

/**
 * Validates continuous profiles exported by an SDK profiler to CloudWatch Profiles, by querying the
 * Pyroscope-compatible query API ({@link ProfilesService}) and asserting the results against the
 * expected-data template.
 *
 * <p>The expected template is a single JSON object whose values are regex patterns, mirroring the
 * regex-per-field convention of {@link CWLogValidator} and {@link PromQLValidator}. Only {@code
 * profileType} is required; every other key is an optional, independent check:
 *
 * <pre>
 * {
 *   "profileType": "^[^:]+:wall:nanoseconds:.*$",       // must match one advertised profile type ID
 *   "labelNames":  ["operation", "thread.state"],        // each must exist on the series
 *   "labelValues": { "operation": ["^GET /a$", "^GET /b$"] }, // each regex must match >=1 value
 *   "functions":   ["^com\\.amazon\\.sampleapp\\..+"],  // each must match >=1 flame-graph frame
 *   "absentFunctions": ["\\.so\\."],                     // no flame-graph frame may match
 *   "minTotal":    "1",                                  // flame-graph total must be >= this
 *   "absentLabelNames": ["thread.state"],                // each must NOT exist on the series
 *   "minWindows":  "3",                                  // data in >=3 consecutive export windows
 *   "operations": {                                      // flame graph of one operation's samples
 *     "GET /a": { "functions": ["\\.handleA$"], "absentFunctions": ["\\.handleB$"] }
 *   }
 * }
 * </pre>
 *
 * <p>Label checks are scoped to the resolved profile type (a {@code __profile_type__} matcher is
 * added to the selector), so a label carried by one profile type of the service cannot satisfy a
 * check about another (e.g. allocation samples satisfying a wall-sample label check).
 *
 * <p>The concrete profile type ID (Pyroscope's {@code name:sample_type:sample_unit:period_type:
 * period_unit}) is resolved at query time from {@code ProfileTypes} by the {@code profileType}
 * regex, so templates pin only the parts a language's profiler controls (sample type and unit), not
 * how the backend names the series.
 *
 * <p>Label names are compared after normalization, because a query surface may expose an OTLP
 * attribute bare ({@code thread.state}), prefixed ({@code @sample.thread.state}) or with dots
 * replaced by underscores ({@code thread_state}). The same key in the template therefore matches any
 * of those spellings.
 *
 * <p>Profiles are ingested asynchronously and become queryable only after the backend aggregates
 * them, so every check is retried until it passes or the retry budget runs out.
 */
@Log4j2
public class ProfileValidator implements IValidator {
  private static final int DEFAULT_MAX_RETRY_COUNT = 60;
  private static final int DEFAULT_LOOKBACK_MINUTES = 30;
  private static final String DEFAULT_LABEL_SELECTOR = "{@resource.service.name=\"{{serviceName}}\"}";
  private static final Pattern SCOPE_PREFIX = Pattern.compile("^@[A-Za-z]+\\.");
  private static final ObjectMapper OBJECT_MAPPER =
      new ObjectMapper().enable(DeserializationFeature.ACCEPT_SINGLE_VALUE_AS_ARRAY);
  private static final String PROFILE_TYPE_LABEL = "__profile_type__";
  private static final String OPERATION_LABEL = "operation";

  private final MustacheHelper mustacheHelper = new MustacheHelper();
  private Context context;
  private ValidationConfig validationConfig;
  private FileConfig expectedProfileTemplate;
  private ProfilesService profilesService;
  private int maxRetryCount;

  public ProfileValidator(ProfilesService profilesService) {
    this.profilesService = profilesService;
  }

  @Override
  public void init(
      Context context, ValidationConfig validationConfig, FileConfig expectedProfileTemplate)
      throws Exception {
    this.context = context;
    this.validationConfig = validationConfig;
    this.expectedProfileTemplate = expectedProfileTemplate;
    this.maxRetryCount = DEFAULT_MAX_RETRY_COUNT;
  }

  @Override
  public void validate() throws Exception {
    final ExpectedProfile expected = getExpectedProfile();
    final String selector =
        render(
            validationConfig.getProfileLabelSelector() != null
                ? validationConfig.getProfileLabelSelector()
                : DEFAULT_LABEL_SELECTOR);
    final int lookbackMinutes =
        validationConfig.getProfileLookbackMinutes() != null
            ? validationConfig.getProfileLookbackMinutes()
            : DEFAULT_LOOKBACK_MINUTES;
    log.info("Expected profile: {} (selector {})", expected, selector);

    RetryHelper.retry(
        this.maxRetryCount,
        () -> {
          long end = System.currentTimeMillis();
          long start = end - lookbackMinutes * 60_000L;

          String profileTypeId = resolveProfileTypeId(expected.getProfileType(), start, end);
          String typedSelector = withMatcher(selector, PROFILE_TYPE_LABEL, profileTypeId);
          checkLabelNames(expected, typedSelector, start, end);
          checkAbsentLabelNames(expected, typedSelector, start, end);
          checkLabelValues(expected, typedSelector, start, end);
          checkFlameGraph(expected, profileTypeId, selector, start, end);
          checkOperations(expected, profileTypeId, selector, typedSelector, start, end);
          checkWindows(expected, profileTypeId, selector, start, end);
        });

    log.info("Profile validation passed for {} (selector {})", expected.getProfileType(), selector);
  }

  /** Pick the advertised profile type ID matching the template's {@code profileType} regex. */
  private String resolveProfileTypeId(String profileTypePattern, long start, long end)
      throws Exception {
    Pattern pattern = Pattern.compile(profileTypePattern);
    JsonNode types = field(profilesService.profileTypes(start, end), "profileTypes", "profile_types");
    List<String> seen = new ArrayList<>();
    for (JsonNode type : types) {
      String id = type.path("ID").asText(type.path("id").asText());
      seen.add(id);
      if (pattern.matcher(id).find()) {
        return id;
      }
    }
    log.info("No profile type matching {} yet; advertised: {}", profilePatternLog(pattern), seen);
    throw new BaseException(ExceptionCode.EXPECTED_METRIC_NOT_FOUND);
  }

  private void checkLabelNames(ExpectedProfile expected, String selector, long start, long end)
      throws Exception {
    if (expected.getLabelNames() == null || expected.getLabelNames().isEmpty()) {
      return;
    }
    List<String> actual = labelNames(selector, start, end);
    for (String name : expected.getLabelNames()) {
      if (findLabel(actual, name) == null) {
        log.info("Label '{}' not present yet on {}; labels: {}", name, selector, actual);
        throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
      }
    }
  }

  private void checkLabelValues(ExpectedProfile expected, String selector, long start, long end)
      throws Exception {
    if (expected.getLabelValues() == null || expected.getLabelValues().isEmpty()) {
      return;
    }
    List<String> names = labelNames(selector, start, end);
    for (Map.Entry<String, List<String>> entry : expected.getLabelValues().entrySet()) {
      String actualName = findLabel(names, entry.getKey());
      if (actualName == null) {
        log.info("Label '{}' not present yet on {}; labels: {}", entry.getKey(), selector, names);
        throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
      }
      List<String> values =
          textList(field(profilesService.labelValues(actualName, selector, start, end), "names"));
      for (String regex : entry.getValue()) {
        Pattern pattern = Pattern.compile(regex);
        if (values.stream().noneMatch(v -> pattern.matcher(v).find())) {
          log.info("No value of '{}' matches {}; values: {}", actualName, regex, values);
          throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
        }
      }
    }
  }

  private void checkFlameGraph(
      ExpectedProfile expected, String profileTypeId, String selector, long start, long end)
      throws Exception {
    if (isEmpty(expected.getFunctions())
        && isEmpty(expected.getAbsentFunctions())
        && expected.getMinTotal() == null) {
      return;
    }
    JsonNode flamegraph =
        profilesService.selectMergeStacktraces(profileTypeId, selector, start, end).path("flamegraph");

    if (expected.getMinTotal() != null) {
      long total = parseLong(flamegraph.path("total").asText("0"));
      long min = parseLong(expected.getMinTotal());
      if (total < min) {
        log.info("Flame graph total {} below expected minimum {} for {}", total, min, profileTypeId);
        throw new BaseException(ExceptionCode.EXPECTED_METRIC_NOT_FOUND);
      }
    }
    checkFrames(
        flamegraph, expected.getFunctions(), expected.getAbsentFunctions(), profileTypeId);
  }

  /**
   * Request attribution: for each operation in {@code operations}, the flame graph of only the
   * samples carrying that operation must contain its {@code functions} and none of its {@code
   * absentFunctions}. This catches samples attributed to the wrong request, which label-existence
   * checks cannot.
   */
  private void checkOperations(
      ExpectedProfile expected,
      String profileTypeId,
      String selector,
      String typedSelector,
      long start,
      long end)
      throws Exception {
    if (expected.getOperations() == null || expected.getOperations().isEmpty()) {
      return;
    }
    List<String> names = labelNames(typedSelector, start, end);
    String operationLabel = findLabel(names, OPERATION_LABEL);
    if (operationLabel == null) {
      log.info(
          "Label '{}' not present yet on {}; labels: {}", OPERATION_LABEL, typedSelector, names);
      throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
    }
    for (Map.Entry<String, ExpectedFrames> entry : expected.getOperations().entrySet()) {
      String operationSelector = withMatcher(selector, operationLabel, entry.getKey());
      JsonNode flamegraph =
          profilesService
              .selectMergeStacktraces(profileTypeId, operationSelector, start, end)
              .path("flamegraph");
      checkFrames(
          flamegraph,
          entry.getValue().getFunctions(),
          entry.getValue().getAbsentFunctions(),
          profileTypeId + " " + operationSelector);
    }
  }

  /**
   * Every {@code functions} regex must match a frame of the flame graph and no {@code
   * absentFunctions} regex may. Absent frames are only checked once the graph has frames, so an
   * empty graph (no data yet) waits instead of passing.
   */
  private static void checkFrames(
      JsonNode flamegraph, List<String> functions, List<String> absentFunctions, String what)
      throws BaseException {
    List<String> frames = textList(flamegraph.path("names"));
    for (String function : nullToEmpty(functions)) {
      Pattern pattern = Pattern.compile(function);
      if (frames.stream().noneMatch(f -> pattern.matcher(f).find())) {
        log.info("No frame of {} matches {} ({} frames)", what, function, frames.size());
        throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
      }
    }
    if (isEmpty(absentFunctions)) {
      return;
    }
    if (frames.stream().noneMatch(f -> !"total".equals(f))) {
      log.info("No frames yet for {}; waiting for data before checking absent frames", what);
      throw new BaseException(ExceptionCode.EXPECTED_METRIC_NOT_FOUND);
    }
    for (String absent : absentFunctions) {
      Pattern pattern = Pattern.compile(absent);
      for (String frame : frames) {
        if (pattern.matcher(frame).find()) {
          log.error("Frame '{}' of {} matches forbidden {}", frame, what, absent);
          throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
        }
      }
    }
  }

  /** Each label in {@code absentLabelNames} must NOT exist on the service's series. */
  private void checkAbsentLabelNames(
      ExpectedProfile expected, String selector, long start, long end) throws Exception {
    if (expected.getAbsentLabelNames() == null || expected.getAbsentLabelNames().isEmpty()) {
      return;
    }
    List<String> actual = labelNames(selector, start, end);
    if (actual.isEmpty()) {
      // No data yet: an absent label would trivially "pass", so wait for data instead.
      log.info("No labels yet on {}; waiting for data before checking absent labels", selector);
      throw new BaseException(ExceptionCode.EXPECTED_METRIC_NOT_FOUND);
    }
    for (String name : expected.getAbsentLabelNames()) {
      String found = findLabel(actual, name);
      if (found != null) {
        log.error("Label '{}' must be absent on {} but is present as '{}'", name, selector, found);
        throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
      }
    }
  }

  /**
   * Sustained export: the profile must have data in at least {@code minWindows} consecutive
   * {@code windowSeconds}-wide windows (default 60s, the profiler's export window). Each window is
   * one JFR rotation exported, so this proves the profiler keeps rotating and exporting, not just
   * once.
   */
  private void checkWindows(
      ExpectedProfile expected, String profileTypeId, String selector, long start, long end)
      throws Exception {
    if (expected.getMinWindows() == null) {
      return;
    }
    int min = (int) parseLong(expected.getMinWindows());
    long stepSeconds =
        expected.getWindowSeconds() != null ? parseLong(expected.getWindowSeconds()) : 60L;
    JsonNode series =
        field(
            profilesService.selectSeries(profileTypeId, selector, start, end, stepSeconds),
            "series");
    int longest = longestConsecutiveRun(series, stepSeconds * 1000L);
    if (longest < min) {
      log.info(
          "Only {} consecutive {}s window(s) with data for {} (need {})",
          longest,
          stepSeconds,
          profileTypeId,
          min);
      throw new BaseException(ExceptionCode.EXPECTED_METRIC_NOT_FOUND);
    }
    log.info("{} consecutive {}s windows with data for {}", longest, stepSeconds, profileTypeId);
  }

  /**
   * Longest run of consecutive points (timestamps exactly {@code stepMs} apart) with a value > 0,
   * across all returned series merged by timestamp.
   */
  @VisibleForTesting
  static int longestConsecutiveRun(JsonNode series, long stepMs) {
    java.util.TreeSet<Long> withData = new java.util.TreeSet<>();
    for (JsonNode s : series) {
      for (JsonNode p : s.path("points")) {
        if (p.path("value").asDouble(0) > 0) {
          withData.add(p.path("timestamp").asLong());
        }
      }
    }
    int longest = 0;
    int run = 0;
    Long prev = null;
    for (long ts : withData) {
      run = (prev != null && ts - prev == stepMs) ? run + 1 : 1;
      longest = Math.max(longest, run);
      prev = ts;
    }
    return longest;
  }

  private List<String> labelNames(String selector, long start, long end) throws Exception {
    return textList(field(profilesService.labelNames(selector, start, end), "names"));
  }

  /**
   * Return the actual label name that {@code expected} refers to, or null. Both sides are
   * normalized (scope prefix such as {@code @sample.} stripped, dots mapped to underscores,
   * lowercased) so {@code thread.state}, {@code @sample.thread.state} and {@code thread_state} all
   * match.
   */
  @VisibleForTesting
  static String findLabel(List<String> actualNames, String expected) {
    String want = normalizeLabel(expected);
    for (String actual : actualNames) {
      if (normalizeLabel(actual).equals(want)) {
        return actual;
      }
    }
    return null;
  }

  private static String normalizeLabel(String name) {
    return SCOPE_PREFIX.matcher(name).replaceFirst("").replace('.', '_').toLowerCase(Locale.ROOT);
  }

  /** First present field among {@code names} (JSON may use camelCase or snake_case). */
  private static JsonNode field(JsonNode node, String... names) {
    for (String name : names) {
      JsonNode value = node.path(name);
      if (!value.isMissingNode()) {
        return value;
      }
    }
    return OBJECT_MAPPER.createArrayNode();
  }

  private static List<String> textList(JsonNode array) {
    List<String> out = new ArrayList<>();
    for (Iterator<JsonNode> it = array.elements(); it.hasNext(); ) {
      out.add(it.next().asText());
    }
    return out;
  }

  /**
   * Add a {@code name="value"} matcher to a label selector such as {@code {a="b"}}, giving {@code
   * {a="b",name="value"}}.
   */
  @VisibleForTesting
  static String withMatcher(String selector, String name, String value) {
    String trimmed = selector.trim();
    if (!trimmed.endsWith("}")) {
      throw new IllegalArgumentException("label selector must end with '}': " + selector);
    }
    String body = trimmed.substring(0, trimmed.length() - 1).trim();
    String escaped = value.replace("\\", "\\\\").replace("\"", "\\\"");
    String matcher = name + "=\"" + escaped + "\"";
    return body.equals("{") ? "{" + matcher + "}" : body + "," + matcher + "}";
  }

  private static boolean isEmpty(List<?> list) {
    return list == null || list.isEmpty();
  }

  private static List<String> nullToEmpty(List<String> list) {
    return list == null ? new ArrayList<>() : list;
  }

  private static long parseLong(String text) {
    try {
      return Long.parseLong(text.trim());
    } catch (NumberFormatException e) {
      return 0L;
    }
  }

  private static String profilePatternLog(Pattern pattern) {
    return "/" + pattern.pattern() + "/";
  }

  private String render(String value) {
    return value
        .replace("{{serviceName}}", context.getServiceName() != null ? context.getServiceName() : "")
        .replace("{{region}}", context.getRegion() != null ? context.getRegion() : "");
  }

  private ExpectedProfile getExpectedProfile() throws Exception {
    ExpectedProfile expected =
        parseExpected(mustacheHelper.render(this.expectedProfileTemplate, context));
    if (expected.getProfileType() == null || expected.getProfileType().isEmpty()) {
      throw new BaseException(
          ExceptionCode.DATA_MODEL_NOT_MATCHED, "profile template must set 'profileType'");
    }
    return expected;
  }

  /** Parse a rendered expected-data template. */
  @VisibleForTesting
  static ExpectedProfile parseExpected(String rendered) throws Exception {
    return OBJECT_MAPPER.readValue(rendered, ExpectedProfile.class);
  }

  /**
   * The expected-data template for one profile type. Values are regexes except label names,
   * operation names, minTotal, minWindows and windowSeconds.
   */
  @Data
  public static class ExpectedProfile {
    private String profileType;
    private List<String> labelNames;
    private List<String> absentLabelNames;
    private Map<String, List<String>> labelValues;
    private List<String> functions;
    private List<String> absentFunctions;
    private Map<String, ExpectedFrames> operations;
    private String minTotal;
    private String minWindows;
    private String windowSeconds;
  }

  /** Frames required in and forbidden from one operation's flame graph (regexes). */
  @Data
  public static class ExpectedFrames {
    private List<String> functions;
    private List<String> absentFunctions;
  }

  @VisibleForTesting
  public void setMaxRetryCount(int maxRetryCount) {
    this.maxRetryCount = maxRetryCount;
  }
}
