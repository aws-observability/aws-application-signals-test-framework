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
 *   "labelNames":  ["operation", "thread.state"],        // each must exist on the service's series
 *   "labelValues": { "operation": "^GET /.+$" },         // >=1 value of each label must match
 *   "functions":   ["^com\\.amazon\\.sampleapp\\..+"],  // each must match >=1 flame-graph frame
 *   "minTotal":    "1",                                  // flame-graph total must be >= this
 *   "absentLabelNames": ["thread.state"],                // each must NOT exist on the series
 *   "minWindows":  "3"                                   // data in >=3 consecutive export windows
 * }
 * </pre>
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
  private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

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
          checkLabelNames(expected, selector, start, end);
          checkAbsentLabelNames(expected, selector, start, end);
          checkLabelValues(expected, selector, start, end);
          checkFlameGraph(expected, profileTypeId, selector, start, end);
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
    for (Map.Entry<String, String> entry : expected.getLabelValues().entrySet()) {
      String actualName = findLabel(names, entry.getKey());
      if (actualName == null) {
        log.info("Label '{}' not present yet on {}; labels: {}", entry.getKey(), selector, names);
        throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
      }
      Pattern pattern = Pattern.compile(entry.getValue());
      List<String> values =
          textList(field(profilesService.labelValues(actualName, selector, start, end), "names"));
      if (values.stream().noneMatch(v -> pattern.matcher(v).find())) {
        log.info("No value of '{}' matches {}; values: {}", actualName, entry.getValue(), values);
        throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
      }
    }
  }

  private void checkFlameGraph(
      ExpectedProfile expected, String profileTypeId, String selector, long start, long end)
      throws Exception {
    boolean checkFunctions = expected.getFunctions() != null && !expected.getFunctions().isEmpty();
    if (!checkFunctions && expected.getMinTotal() == null) {
      return;
    }
    JsonNode flamegraph =
        profilesService.selectMergeStacktraces(profileTypeId, selector, start, end).path("flamegraph");
    List<String> frames = textList(flamegraph.path("names"));

    if (expected.getMinTotal() != null) {
      long total = parseLong(flamegraph.path("total").asText("0"));
      long min = parseLong(expected.getMinTotal());
      if (total < min) {
        log.info("Flame graph total {} below expected minimum {} for {}", total, min, profileTypeId);
        throw new BaseException(ExceptionCode.EXPECTED_METRIC_NOT_FOUND);
      }
    }
    if (checkFunctions) {
      for (String function : expected.getFunctions()) {
        Pattern pattern = Pattern.compile(function);
        if (frames.stream().noneMatch(f -> pattern.matcher(f).find())) {
          log.info("No frame of {} matches {} ({} frames)", profileTypeId, function, frames.size());
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
    String rendered = mustacheHelper.render(this.expectedProfileTemplate, context);
    ExpectedProfile expected = OBJECT_MAPPER.readValue(rendered, ExpectedProfile.class);
    if (expected.getProfileType() == null || expected.getProfileType().isEmpty()) {
      throw new BaseException(
          ExceptionCode.DATA_MODEL_NOT_MATCHED, "profile template must set 'profileType'");
    }
    return expected;
  }

  /** The expected-data template for one profile type. All values are regexes except minTotal. */
  @Data
  public static class ExpectedProfile {
    private String profileType;
    private List<String> labelNames;
    private List<String> absentLabelNames;
    private Map<String, String> labelValues;
    private List<String> functions;
    private String minTotal;
    private String minWindows;
    private String windowSeconds;
  }

  @VisibleForTesting
  public void setMaxRetryCount(int maxRetryCount) {
    this.maxRetryCount = maxRetryCount;
  }
}
