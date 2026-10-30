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
 *   "minWindows":  "3",                                  // data in >=3 consecutive windows
 *   "windowSeconds": "300",                              // width of those windows (default 60)
 *   "exactLabelValues": { "process.pid": ["1234"] },     // the label's values are exactly these
 *   "labelValueCounts": { "service.instance.id": "1" },  // the label has exactly this many values
 *   "minLabelValueCounts": { "thread.name": "30" },      // ... at least this many values
 *   "allowedLabelValues": { "operation": ["GET /a", "GET /b"] }, // no other value (RE2)
 *   "hotspots": [ { "function": "\\.Thread\\.run( |$)", "minShare": "0.5" } ], // share of total
 *   "expectedTotal": "600000000000",                     // total must equal this (data not dropped)
 *   "totalTolerance": "0.02",                            // ... within this fraction (default 0.02)
 *   "queryStartMs": "...", "queryEndMs": "...",          // fixed query window instead of lookback
 *   "reportOnly": "true", "reportOnlyReason": "...",     // not enforced: ~1 min of retries, then
 *                                                        // always passes, logging the outcome
 *   "operations": {                                      // flame graph of one operation's samples
 *     "GET /a": {
 *       "functions": ["\\.handleA( |$)"], "absentFunctions": ["\\.handleB( |$)"],
 *       "hotspots": [ { "function": "\\.handleA( |$)", "minShare": "0.8" } ],
 *       "allLabelValuesMatch": { "thread.name": "http-nio-8080-exec-[0-9]+" } // every sample's value
 *     }
 *   },
 *   "traces": {                                          // flame graph of one trace's samples
 *     "4bf92f3577b34da6a3ce929d0e0e4736": {              // (32-hex trace ID)
 *       "functions": ["\\.handleA( |$)"], "absentFunctions": ["\\.handleB( |$)"]
 *     }
 *   },
 *   "unlinkedTraces": ["0af7651916cd43dd8448eb211c80319c"] // no sample may link to these traces
 * }
 * </pre>
 *
 * <p>Deploy-time values (e.g. each JVM's PID) reach templates through {@code
 * --profile-context-file}, as {@code {{profileContext.<key>}}}.
 *
 * <p>CloudWatch Profiles appends the source file and line to Java frame names in the flame graph
 * (e.g. {@code com.example.Foo.bar Foo.java:42}), while native frames stay bare ({@code
 * start_thread}). End a Java frame regex with {@code ( |$)} rather than {@code $}.
 *
 * <p>Label checks are scoped to the resolved profile type, so a label carried by one profile type of
 * the service cannot satisfy a check about another (e.g. allocation samples satisfying a wall-sample
 * label check). CloudWatch's {@code LabelNames}/{@code LabelValues} ignore {@code __profile_type__}
 * and sample-attribute matchers, so they only supply candidate names and values for the whole
 * service; whether a label or value is actually on the checked profile type's samples is decided by
 * a {@code SelectMergeStacktraces} query for that type with a matcher on it (non-empty result).
 * {@code allLabelValuesMatch} regexes and {@code allowedLabelValues} values (joined into one
 * alternation) go to the backend as a {@code !~} matcher, so they use its (RE2, fully anchored)
 * syntax; every other regex is a Java regex matched with {@code find()}.
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
 * them, so every check is retried until it passes or the retry budget runs out. A {@code
 * reportOnly} check gets a short budget and never fails: it logs whether it would have passed.
 */
@Log4j2
public class ProfileValidator implements IValidator {
  private static final int DEFAULT_MAX_RETRY_COUNT = 60;
  private static final int DEFAULT_LOOKBACK_MINUTES = 30;
  private static final String DEFAULT_LABEL_SELECTOR = "{@resource.service.name=\"{{serviceName}}\"}";
  private static final Pattern SCOPE_PREFIX = Pattern.compile("^@[A-Za-z]+\\.");
  private static final ObjectMapper OBJECT_MAPPER =
      new ObjectMapper().enable(DeserializationFeature.ACCEPT_SINGLE_VALUE_AS_ARRAY);
  private static final String ANY_VALUE = ".+";
  private static final double DEFAULT_TOTAL_TOLERANCE = 0.02;
  // A reportOnly check retries for about a minute (10 s apart) instead of the full budget.
  private static final int REPORT_ONLY_MAX_RETRY_COUNT = 6;
  private static final String OPERATION_LABEL = "operation";
  // Selects the samples whose trace link (OTLP Sample -> Link) has this trace ID.
  private static final String TRACE_ID_MATCHER = "__trace_id__";
  private static final Pattern TRACE_ID = Pattern.compile("^[0-9a-f]{32}$");

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

    // reportOnly: not enforced. Retry briefly, then always pass, reporting what the check concluded.
    boolean reportOnly = "true".equalsIgnoreCase(expected.getReportOnly());
    int retries =
        reportOnly ? Math.min(this.maxRetryCount, REPORT_ONLY_MAX_RETRY_COUNT) : this.maxRetryCount;
    try {
      runChecks(expected, selector, lookbackMinutes, retries);
    } catch (Exception e) {
      if (!reportOnly) {
        throw e;
      }
      reportNotEnforced(expected, false, e);
      return;
    }
    if (reportOnly) {
      reportNotEnforced(expected, true, null);
      return;
    }
    log.info("Profile validation passed for {} (selector {})", expected.getProfileType(), selector);
  }

  private void runChecks(ExpectedProfile expected, String selector, int lookbackMinutes, int retries)
      throws Exception {
    // A bad trace ID is a deploy problem (e.g. a request that returned none), not missing data: fail
    // now instead of retrying.
    if (expected.getTraces() != null) {
      expected.getTraces().keySet().forEach(ProfileValidator::requireTraceId);
    }
    nullToEmpty(expected.getUnlinkedTraces()).forEach(ProfileValidator::requireTraceId);
    RetryHelper.retry(
        retries,
        () -> {
          // A fixed window (queryStartMs/queryEndMs, e.g. exactly the export windows an
          // expectedTotal was counted over) takes precedence over the lookback.
          long end =
              expected.getQueryEndMs() != null
                  ? parseLong(expected.getQueryEndMs())
                  : System.currentTimeMillis();
          long start =
              expected.getQueryStartMs() != null
                  ? parseLong(expected.getQueryStartMs())
                  : end - lookbackMinutes * 60_000L;

          String profileTypeId = resolveProfileTypeId(expected.getProfileType(), start, end);
          checkFlameGraph(expected, profileTypeId, selector, start, end);
          checkLabelNames(expected, profileTypeId, selector, start, end);
          checkAbsentLabelNames(expected, profileTypeId, selector, start, end);
          checkLabelValues(expected, profileTypeId, selector, start, end);
          checkAllowedLabelValues(expected, profileTypeId, selector, start, end);
          checkExactLabelValues(expected, profileTypeId, selector, start, end);
          checkLabelValueCounts(expected, profileTypeId, selector, start, end);
          checkMinLabelValueCounts(expected, profileTypeId, selector, start, end);
          checkOperations(expected, profileTypeId, selector, start, end);
          checkTraces(expected, profileTypeId, selector, start, end);
          checkUnlinkedTraces(expected, profileTypeId, selector, start, end);
          checkWindows(expected, profileTypeId, selector, start, end);
        });
  }

  /**
   * Report the outcome of a {@code reportOnly} (not enforced) check: it passes either way, but the
   * log says whether it would have passed and why not, with {@code reportOnlyReason} saying why it
   * is not enforced. On GitHub Actions the line is also a warning annotation on the run.
   */
  private static void reportNotEnforced(ExpectedProfile expected, boolean passed, Exception failure) {
    String outcome;
    if (passed) {
      outcome = "would pass";
    } else {
      String reason =
          failure instanceof BaseException && ((BaseException) failure).getMessage() != null
              ? ((BaseException) failure).getMessage()
              : String.valueOf(failure);
      outcome = "would FAIL: " + reason;
    }
    String message =
        String.format(
            "NOT ENFORCED: %s check %s. %s",
            expected.getProfileType(),
            outcome,
            expected.getReportOnlyReason() != null ? expected.getReportOnlyReason() : "");
    log.warn(message);
    if (System.getenv("GITHUB_ACTIONS") != null) {
      System.out.println("::warning title=Profiler check not enforced::" + message);
    }
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

  /** Each label in {@code labelNames} must be on samples of the profile type. */
  private void checkLabelNames(
      ExpectedProfile expected, String profileTypeId, String selector, long start, long end)
      throws Exception {
    if (isEmpty(expected.getLabelNames())) {
      return;
    }
    List<String> names = labelNames(selector, start, end);
    for (String name : expected.getLabelNames()) {
      String actual = requireLabel(names, name, selector);
      if (!hasSamples(profileTypeId, withMatcher(selector, actual, "=~", ANY_VALUE), start, end)) {
        log.info("Label '{}' not on any {} sample yet ({})", actual, profileTypeId, selector);
        throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
      }
    }
  }

  /** Each {@code labelValues} regex must match a value carried by samples of the profile type. */
  private void checkLabelValues(
      ExpectedProfile expected, String profileTypeId, String selector, long start, long end)
      throws Exception {
    if (expected.getLabelValues() == null || expected.getLabelValues().isEmpty()) {
      return;
    }
    List<String> names = labelNames(selector, start, end);
    for (Map.Entry<String, List<String>> entry : expected.getLabelValues().entrySet()) {
      String actualName = requireLabel(names, entry.getKey(), selector);
      List<String> candidates = labelValues(actualName, selector, start, end);
      for (String regex : entry.getValue()) {
        Pattern pattern = Pattern.compile(regex);
        boolean found = false;
        for (String value : candidates) {
          if (pattern.matcher(value).find()
              && hasSamples(
                  profileTypeId, withMatcher(selector, actualName, "=", value), start, end)) {
            found = true;
            break;
          }
        }
        if (!found) {
          log.info(
              "No {} sample has a '{}' value matching {}; service-wide values: {}",
              profileTypeId,
              actualName,
              regex,
              candidates);
          throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
        }
      }
    }
  }

  /**
   * Identity: each {@code exactLabelValues} label's values on samples of the profile type must be
   * exactly the given set (e.g. a service's {@code process.pid} is only the PID of its own JVM).
   */
  private void checkExactLabelValues(
      ExpectedProfile expected, String profileTypeId, String selector, long start, long end)
      throws Exception {
    if (expected.getExactLabelValues() == null || expected.getExactLabelValues().isEmpty()) {
      return;
    }
    List<String> names = labelNames(selector, start, end);
    for (Map.Entry<String, List<String>> entry : expected.getExactLabelValues().entrySet()) {
      java.util.Set<String> want = new java.util.TreeSet<>(entry.getValue());
      if (want.isEmpty() || want.stream().anyMatch(v -> v == null || v.trim().isEmpty())) {
        throw new BaseException(
            ExceptionCode.DATA_MODEL_NOT_MATCHED,
            "exactLabelValues '"
                + entry.getKey()
                + "' has an empty expected value; check the --profile-context passed in");
      }
      String actualName = requireLabel(names, entry.getKey(), selector);
      java.util.Set<String> got =
          new java.util.TreeSet<>(scopedValues(profileTypeId, selector, actualName, start, end));
      if (!got.equals(want)) {
        log.info(
            "'{}' values on {} samples are {}, expected exactly {}",
            actualName,
            profileTypeId,
            got,
            want);
        throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
      }
    }
  }

  /** Each {@code labelValueCounts} label must have exactly that many values on the samples. */
  private void checkLabelValueCounts(
      ExpectedProfile expected, String profileTypeId, String selector, long start, long end)
      throws Exception {
    if (expected.getLabelValueCounts() == null || expected.getLabelValueCounts().isEmpty()) {
      return;
    }
    List<String> names = labelNames(selector, start, end);
    for (Map.Entry<String, String> entry : expected.getLabelValueCounts().entrySet()) {
      String actualName = requireLabel(names, entry.getKey(), selector);
      List<String> got = scopedValues(profileTypeId, selector, actualName, start, end);
      long want = parseLong(entry.getValue());
      if (got.size() != want) {
        log.info(
            "'{}' has {} value(s) on {} samples, expected {}: {}",
            actualName,
            got.size(),
            profileTypeId,
            want,
            got);
        throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
      }
    }
  }

  /**
   * Each {@code minLabelValueCounts} label must have at least that many distinct values on samples
   * of the profile type (e.g. wall samples cover most of the JVM's threads). Stops counting once
   * the minimum is reached.
   */
  private void checkMinLabelValueCounts(
      ExpectedProfile expected, String profileTypeId, String selector, long start, long end)
      throws Exception {
    if (expected.getMinLabelValueCounts() == null || expected.getMinLabelValueCounts().isEmpty()) {
      return;
    }
    List<String> names = labelNames(selector, start, end);
    for (Map.Entry<String, String> entry : expected.getMinLabelValueCounts().entrySet()) {
      long want = requirePositive(entry.getValue(), "minLabelValueCounts '" + entry.getKey() + "'");
      String actualName = requireLabel(names, entry.getKey(), selector);
      List<String> candidates = labelValues(actualName, selector, start, end);
      int found = 0;
      for (String value : candidates) {
        if (hasSamples(profileTypeId, withMatcher(selector, actualName, "=", value), start, end)) {
          found++;
          if (found >= want) {
            break;
          }
        }
      }
      if (found < want) {
        log.info(
            "'{}' has {} distinct value(s) on {} samples, expected at least {} ({} listed"
                + " service-wide)",
            actualName,
            found,
            profileTypeId,
            want,
            candidates.size());
        throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
      }
    }
  }

  /**
   * No sample of the profile type may carry a value of an {@code allowedLabelValues} label outside
   * its list (backend RE2 regexes, fully anchored): no unexpected operation, say. Samples without
   * the label are not affected; combine with {@code labelValues} to also require each value.
   */
  private void checkAllowedLabelValues(
      ExpectedProfile expected, String profileTypeId, String selector, long start, long end)
      throws Exception {
    if (expected.getAllowedLabelValues() == null || expected.getAllowedLabelValues().isEmpty()) {
      return;
    }
    List<String> names = labelNames(selector, start, end);
    for (Map.Entry<String, List<String>> entry : expected.getAllowedLabelValues().entrySet()) {
      String actualName = requireLabel(names, entry.getKey(), selector);
      String allowed = "(" + String.join("|", entry.getValue()) + ")";
      String unexpected =
          withMatcher(
              withMatcher(selector, actualName, "=~", ANY_VALUE), actualName, "!~", allowed);
      if (hasSamples(profileTypeId, unexpected, start, end)) {
        List<String> offenders = new ArrayList<>();
        Pattern allowedJava = Pattern.compile("^" + allowed + "$");
        for (String value : labelValues(actualName, selector, start, end)) {
          if (!allowedJava.matcher(value).matches()
              && hasSamples(
                  profileTypeId, withMatcher(selector, actualName, "=", value), start, end)) {
            offenders.add(value);
          }
        }
        log.error(
            "{} samples carry '{}' values outside {}: {}",
            profileTypeId,
            actualName,
            entry.getValue(),
            offenders);
        throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
      }
    }
  }

  private void checkFlameGraph(
      ExpectedProfile expected, String profileTypeId, String selector, long start, long end)
      throws Exception {
    if (isEmpty(expected.getFunctions())
        && isEmpty(expected.getAbsentFunctions())
        && isEmpty(expected.getHotspots())
        && expected.getMinTotal() == null
        && expected.getExpectedTotal() == null) {
      return;
    }
    JsonNode flamegraph =
        profilesService.selectMergeStacktraces(profileTypeId, selector, start, end).path("flamegraph");
    long total = parseLong(flamegraph.path("total").asText("0"));

    if (expected.getMinTotal() != null) {
      long min = parseLong(expected.getMinTotal());
      if (total < min) {
        log.info("Flame graph total {} below expected minimum {} for {}", total, min, profileTypeId);
        throw new BaseException(ExceptionCode.EXPECTED_METRIC_NOT_FOUND);
      }
    }
    checkExpectedTotal(expected, total, profileTypeId, start, end);
    checkFrames(
        flamegraph, expected.getFunctions(), expected.getAbsentFunctions(), profileTypeId);
    checkHotspots(flamegraph, expected.getHotspots(), profileTypeId);
  }

  /**
   * Nothing dropped between the agent and the backend: the flame-graph total over the query window
   * must equal {@code expectedTotal} (what the agent produced for exactly those export windows)
   * within {@code totalTolerance} (a fraction, default 0.02). Below it, ingestion may still be
   * catching up, so the check waits; above it, the data cannot be explained by what was sent.
   */
  private static void checkExpectedTotal(
      ExpectedProfile expected, long total, String profileTypeId, long start, long end)
      throws BaseException {
    if (expected.getExpectedTotal() == null) {
      return;
    }
    long want = requirePositive(expected.getExpectedTotal(), "expectedTotal");
    double tolerance =
        expected.getTotalTolerance() != null
            ? Double.parseDouble(expected.getTotalTolerance())
            : DEFAULT_TOTAL_TOLERANCE;
    double ratio = (double) total / want;
    String measured =
        String.format(
            "%s total %d is %.1f%% of the expected %d for [%d, %d] (tolerance +/-%.0f%%)",
            profileTypeId, total, 100 * ratio, want, start, end, 100 * tolerance);
    if (ratio < 1 - tolerance) {
      log.info("{}; waiting for the rest", measured);
      throw new BaseException(ExceptionCode.EXPECTED_METRIC_NOT_FOUND, measured);
    }
    if (ratio > 1 + tolerance) {
      log.error("{}: more than was sent", measured);
      throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED, measured + ": more than was sent");
    }
    log.info("{}: matches", measured);
  }

  /**
   * Hot spots: each listed function's share of the flame graph (the summed time of its nodes over
   * the graph total) must be within [minShare, maxShare]. Catches a hot path that moves or
   * disappears, e.g. a handler that stops dominating its request's samples. Waits while the graph
   * is empty.
   */
  private static void checkHotspots(JsonNode flamegraph, List<Hotspot> hotspots, String what)
      throws BaseException {
    if (isEmpty(hotspots)) {
      return;
    }
    long total = parseLong(flamegraph.path("total").asText("0"));
    if (total <= 0) {
      log.info("No samples yet for {}; waiting before checking hot spots", what);
      throw new BaseException(ExceptionCode.EXPECTED_METRIC_NOT_FOUND);
    }
    for (Hotspot hotspot : hotspots) {
      double share = (double) frameTime(flamegraph, hotspot.getFunction()) / total;
      double min = hotspot.getMinShare() != null ? Double.parseDouble(hotspot.getMinShare()) : 0;
      double max = hotspot.getMaxShare() != null ? Double.parseDouble(hotspot.getMaxShare()) : 1;
      if (share < min || share > max) {
        log.error(
            "{} of {} is {}% of its samples, expected {}%-{}%",
            hotspot.getFunction(),
            what,
            String.format("%.1f", 100 * share),
            String.format("%.0f", 100 * min),
            String.format("%.0f", 100 * max));
        throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
      }
      log.info(
          "{} of {} is {}% of its samples", hotspot.getFunction(), what, String.format("%.1f", 100 * share));
    }
  }

  /**
   * Summed total time of the flame-graph nodes whose frame name matches {@code regex}. The
   * Pyroscope flamebearer stores each level as groups of four numbers: offset, total, self, name
   * index. A recursive frame (a node nested under a node of the same function) would be counted
   * more than once; hot-spot functions should not be recursive.
   */
  @VisibleForTesting
  static long frameTime(JsonNode flamegraph, String regex) {
    Pattern pattern = Pattern.compile(regex);
    List<String> names = textList(flamegraph.path("names"));
    long sum = 0;
    for (JsonNode level : flamegraph.path("levels")) {
      JsonNode values = level.path("values");
      for (int i = 0; i + 3 < values.size(); i += 4) {
        int nameIndex = values.get(i + 3).asInt();
        if (nameIndex >= 0
            && nameIndex < names.size()
            && pattern.matcher(names.get(nameIndex)).find()) {
          sum += values.get(i + 1).asLong();
        }
      }
    }
    return sum;
  }

  private static long requirePositive(String value, String what) throws BaseException {
    long parsed = value == null ? 0 : parseLong(value);
    if (parsed <= 0) {
      throw new BaseException(
          ExceptionCode.DATA_MODEL_NOT_MATCHED,
          what + " must be a positive number but is '" + value
              + "'; check the --profile-context-file passed in");
    }
    return parsed;
  }

  /**
   * Request attribution: for each operation in {@code operations}, the flame graph of only the
   * samples carrying that operation must contain its {@code functions} and none of its {@code
   * absentFunctions}. This catches samples attributed to the wrong request, which label-existence
   * checks cannot.
   */
  private void checkOperations(
      ExpectedProfile expected, String profileTypeId, String selector, long start, long end)
      throws Exception {
    if (expected.getOperations() == null || expected.getOperations().isEmpty()) {
      return;
    }
    List<String> names = labelNames(selector, start, end);
    String operationLabel = requireLabel(names, OPERATION_LABEL, selector);
    for (Map.Entry<String, ExpectedFrames> entry : expected.getOperations().entrySet()) {
      String operationSelector = withMatcher(selector, operationLabel, entry.getKey());
      JsonNode flamegraph =
          profilesService
              .selectMergeStacktraces(profileTypeId, operationSelector, start, end)
              .path("flamegraph");
      String what = profileTypeId + " " + operationSelector;
      checkFrames(
          flamegraph, entry.getValue().getFunctions(), entry.getValue().getAbsentFunctions(), what);
      checkHotspots(flamegraph, entry.getValue().getHotspots(), what);
      checkAllLabelValuesMatch(
          entry.getValue().getAllLabelValuesMatch(),
          names,
          profileTypeId,
          operationSelector,
          start,
          end);
    }
  }

  /**
   * Trace correlation: for each trace ID in {@code traces}, the flame graph of only the samples
   * linked to that trace must hold its expected frames and none of its forbidden ones, e.g. a
   * request's own handler and not another route's. Waits while the trace has no samples yet.
   */
  private void checkTraces(
      ExpectedProfile expected, String profileTypeId, String selector, long start, long end)
      throws Exception {
    if (expected.getTraces() == null) {
      return;
    }
    for (Map.Entry<String, ExpectedFrames> entry : expected.getTraces().entrySet()) {
      String traceSelector = withMatcher(selector, TRACE_ID_MATCHER, requireTraceId(entry.getKey()));
      JsonNode flamegraph =
          profilesService
              .selectMergeStacktraces(profileTypeId, traceSelector, start, end)
              .path("flamegraph");
      if (parseLong(flamegraph.path("total").asText("0")) == 0) {
        log.info("No samples linked to trace yet for {} {}", profileTypeId, traceSelector);
        throw new BaseException(ExceptionCode.EXPECTED_METRIC_NOT_FOUND);
      }
      checkFrames(
          flamegraph,
          entry.getValue().getFunctions(),
          entry.getValue().getAbsentFunctions(),
          profileTypeId + " " + traceSelector);
    }
  }

  /**
   * No sample may link to a trace in {@code unlinkedTraces}, e.g. requests whose trace was dropped
   * by sampling: their samples keep the operation but must not point at a trace that was never
   * exported. Only meaningful once the requests' export windows are ingested, so templates using it
   * run after the export accounting, minutes after the requests.
   */
  private void checkUnlinkedTraces(
      ExpectedProfile expected, String profileTypeId, String selector, long start, long end)
      throws Exception {
    for (String traceId : nullToEmpty(expected.getUnlinkedTraces())) {
      String traceSelector = withMatcher(selector, TRACE_ID_MATCHER, requireTraceId(traceId));
      if (hasSamples(profileTypeId, traceSelector, start, end)) {
        log.error("Samples of {} link to trace {}, which should have no link", profileTypeId, traceId);
        throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
      }
    }
  }

  /**
   * A template trace ID must be a valid 32-hex trace ID: an empty one would select every sample, and
   * all zeros is what a request without an active span returns.
   */
  private static String requireTraceId(String traceId) {
    if (traceId == null
        || !TRACE_ID.matcher(traceId).matches()
        || traceId.chars().allMatch(c -> c == '0')) {
      throw new IllegalArgumentException("not a 32-hex trace ID: '" + traceId + "'");
    }
    return traceId;
  }

  /**
   * Every sample selected by {@code selector} must have a value of each label matching its regex
   * (backend RE2 syntax): no sample may match {@code label!~"regex"}. E.g. every sample of a request
   * is on a request-handler thread. Waits while the selector has no samples at all.
   */
  private void checkAllLabelValuesMatch(
      Map<String, String> expected,
      List<String> names,
      String profileTypeId,
      String selector,
      long start,
      long end)
      throws Exception {
    if (expected == null || expected.isEmpty()) {
      return;
    }
    if (!hasSamples(profileTypeId, selector, start, end)) {
      log.info("No {} samples yet on {}", profileTypeId, selector);
      throw new BaseException(ExceptionCode.EXPECTED_METRIC_NOT_FOUND);
    }
    for (Map.Entry<String, String> entry : expected.entrySet()) {
      String actualName = requireLabel(names, entry.getKey(), selector);
      if (hasSamples(
          profileTypeId, withMatcher(selector, actualName, "!~", entry.getValue()), start, end)) {
        log.error(
            "Some {} samples of {} have a '{}' value not matching {}",
            profileTypeId,
            selector,
            actualName,
            entry.getValue());
        throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
      }
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

  /** Each label in {@code absentLabelNames} must NOT be on any sample of the profile type. */
  private void checkAbsentLabelNames(
      ExpectedProfile expected, String profileTypeId, String selector, long start, long end)
      throws Exception {
    if (isEmpty(expected.getAbsentLabelNames())) {
      return;
    }
    if (!hasSamples(profileTypeId, selector, start, end)) {
      // No data yet: an absent label would trivially "pass", so wait for data instead.
      log.info("No {} samples yet on {}; waiting before checking absent labels", profileTypeId, selector);
      throw new BaseException(ExceptionCode.EXPECTED_METRIC_NOT_FOUND);
    }
    List<String> names = labelNames(selector, start, end);
    for (String name : expected.getAbsentLabelNames()) {
      String found = findLabel(names, name);
      if (found != null
          && hasSamples(profileTypeId, withMatcher(selector, found, "=~", ANY_VALUE), start, end)) {
        log.error("Label '{}' must be absent on {} samples but is present", found, profileTypeId);
        throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
      }
    }
  }

  /**
   * Sustained export: the profile must have data in at least {@code minWindows} consecutive
   * {@code windowSeconds}-wide windows (default 60s). Set {@code windowSeconds} to the query
   * resolution the backend actually returns: CloudWatch Profiles answers in 5-minute buckets even
   * when a 60s step is requested, so 60s points are never "consecutive" there. Data in several
   * consecutive buckets proves the profiler keeps rotating and exporting, not just once (3
   * five-minute buckets need data spread over more than 5 minutes, i.e. several 60s profiler
   * windows).
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

  /** Service-wide values of a label: candidates only, since LabelValues is not type-scoped. */
  private List<String> labelValues(String labelName, String selector, long start, long end)
      throws Exception {
    return textList(field(profilesService.labelValues(labelName, selector, start, end), "names"));
  }

  /** The values of {@code labelName} that samples of the profile type actually carry. */
  private List<String> scopedValues(
      String profileTypeId, String selector, String labelName, long start, long end)
      throws Exception {
    List<String> out = new ArrayList<>();
    for (String value : labelValues(labelName, selector, start, end)) {
      if (hasSamples(profileTypeId, withMatcher(selector, labelName, "=", value), start, end)) {
        out.add(value);
      }
    }
    return out;
  }

  /** Whether any sample of the profile type matches the selector (non-empty flame graph). */
  private boolean hasSamples(String profileTypeId, String selector, long start, long end)
      throws Exception {
    JsonNode flamegraph =
        profilesService.selectMergeStacktraces(profileTypeId, selector, start, end).path("flamegraph");
    return parseLong(flamegraph.path("total").asText("0")) > 0;
  }

  /** The actual name of an expected label on the service, or wait (retry) while it is missing. */
  private static String requireLabel(List<String> names, String expected, String selector)
      throws BaseException {
    String actual = findLabel(names, expected);
    if (actual == null) {
      log.info("Label '{}' not present yet on {}; labels: {}", expected, selector, names);
      throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
    }
    return actual;
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
    return withMatcher(selector, name, "=", value);
  }

  /** As {@link #withMatcher(String, String, String)} with the given operator (=, =~, !~). */
  @VisibleForTesting
  static String withMatcher(String selector, String name, String op, String value) {
    String trimmed = selector.trim();
    if (!trimmed.endsWith("}")) {
      throw new IllegalArgumentException("label selector must end with '}': " + selector);
    }
    String body = trimmed.substring(0, trimmed.length() - 1).trim();
    String escaped = value.replace("\\", "\\\\").replace("\"", "\\\"");
    String matcher = name + op + "\"" + escaped + "\"";
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
   * operation names, exactLabelValues/labelValueCounts values, minTotal, minWindows and
   * windowSeconds.
   */
  @Data
  public static class ExpectedProfile {
    private String profileType;
    private List<String> labelNames;
    private List<String> absentLabelNames;
    private Map<String, List<String>> labelValues;
    private Map<String, List<String>> exactLabelValues;
    private Map<String, String> labelValueCounts;
    private Map<String, String> minLabelValueCounts;
    private Map<String, List<String>> allowedLabelValues;
    private List<String> functions;
    private List<String> absentFunctions;
    private List<Hotspot> hotspots;
    private Map<String, ExpectedFrames> operations;
    private Map<String, ExpectedFrames> traces;
    private List<String> unlinkedTraces;
    private String minTotal;
    private String expectedTotal;
    private String totalTolerance;
    private String reportOnly;
    private String reportOnlyReason;
    private String queryStartMs;
    private String queryEndMs;
    private String minWindows;
    private String windowSeconds;
  }

  /**
   * Checks on one operation's samples: frames required in and forbidden from its flame graph
   * (regexes), hot spots, and labels every one of its samples must match ({@code
   * allLabelValuesMatch}).
   */
  @Data
  public static class ExpectedFrames {
    private List<String> functions;
    private List<String> absentFunctions;
    private List<Hotspot> hotspots;
    private Map<String, String> allLabelValuesMatch;
  }

  /** A function (regex) whose share of a flame graph must stay within [minShare, maxShare]. */
  @Data
  public static class Hotspot {
    private String function;
    private String minShare;
    private String maxShare;
  }

  @VisibleForTesting
  public void setMaxRetryCount(int maxRetryCount) {
    this.maxRetryCount = maxRetryCount;
  }
}
