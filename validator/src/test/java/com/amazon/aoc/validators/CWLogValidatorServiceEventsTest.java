package com.amazon.aoc.validators;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.when;

import com.amazon.aoc.exception.BaseException;
import com.amazon.aoc.models.Context;
import com.amazon.aoc.models.ValidationConfig;
import com.amazon.aoc.services.CloudWatchService;
import com.amazonaws.services.logs.model.FilteredLogEvent;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.URL;
import java.nio.charset.Charset;
import java.util.List;
import org.apache.commons.io.IOUtils;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.DisabledIf;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * Drives the shipped .NET EC2 Service Events cw-log templates against representative log records.
 *
 * <p>These are structural tests, not a substitute for a live run. Both the expected template and
 * the actual record pass through the same {@code JsonFlattener}, so a mismatch in nesting produces
 * a different key on one side and fails — which is what makes this worth having. What it verifies:
 * every regex in the template compiles and matches, the template's nesting corresponds to the
 * record's, and {@code --service-events-git-commit-sha} reaches the template through {@link
 * Context}.
 *
 * <p>The fixtures are records captured from a real EC2 run against a distro build containing
 * ServiceEvents, so these are exact contract checks rather than assertions against a
 * reconstruction. Account id, instance id, host name and instance uuid have been replaced with
 * documentation-style placeholders; no template asserts those fields, so the contract being checked
 * is unaffected. Notably they pin behaviour that is easy to get wrong from the source alone: the
 * operation key and {@code url.route} carry NO leading slash for MVC attribute routing
 * ({@code GET exception}, not {@code GET /exception}), and {@code duration_ms},
 * {@code is_partial} and {@code http.response.status_code} arrive as JSON numbers and booleans
 * rather than strings, so template regexes are matched against their {@code toString()} form.
 */
@ExtendWith(MockitoExtension.class)
@DisabledIf("isWindows")
public class CWLogValidatorServiceEventsTest extends ValidatorBaseTest {
    // The fixtures are records captured from a real EC2 run, so the service name and commit SHA
    // below are that run's values rather than invented ones. Keeping the telemetry fields as emitted
    // is the point: it makes these tests a contract check against what the distro and the
    // CloudWatch agent actually produced.
    private static final String SERVICE_NAME = "dotnet-sample-application-manual-1787764999";
    private static final String LOG_GROUP = "/aws/service-events/" + SERVICE_NAME;
    private static final String GIT_COMMIT_SHA = "9e80ff92fe928f0f8240ebf44763c191263b26e7";
    private static final String FIXTURE_ROOT = "log/actual-dotnet-service-events-";

    @Mock
    private CloudWatchService cloudWatchService;

    private final ObjectMapper mapper = new ObjectMapper();

    private Context context;

    static boolean isWindows() {
        return System.getProperty("os.name").toLowerCase().startsWith("win");
    }

    @BeforeEach
    public void setUp() {
        context = initContext();
        context.setServiceName(SERVICE_NAME);
        context.setLogGroup(LOG_GROUP);
        context.setServiceEventsGitCommitSha(GIT_COMMIT_SHA);
    }

    @Test
    public void deploymentEventTemplateMatchesRecord() throws Exception {
        validate("DOTNET_EC2_SERVICE_EVENTS_DEPLOYMENT_EVENT", "deployment-event.json");
    }

    @Test
    public void incidentSnapshotTemplateMatchesRecord() throws Exception {
        validate("DOTNET_EC2_SERVICE_EVENTS_INCIDENT_SNAPSHOT", "incident-snapshot.json");
    }

    @Test
    public void incidentSnapshotLatencyTemplateMatchesRecord() throws Exception {
        validate("DOTNET_EC2_SERVICE_EVENTS_INCIDENT_SNAPSHOT_LATENCY", "incident-snapshot-latency.json");
    }

    /**
     * The exact-SHA assertion has to be able to fail, or it is not testing anything. Validating the
     * exception record against a context carrying a different SHA must be rejected.
     */
    @Test
    public void mismatchedGitCommitShaIsRejected() throws Exception {
        context.setServiceEventsGitCommitSha("0000000000000000000000000000000000000001");
        assertThrows(
                BaseException.class,
                () -> validate("DOTNET_EC2_SERVICE_EVENTS_INCIDENT_SNAPSHOT", "incident-snapshot.json"));
    }

    /**
     * The lookback override is only useful if it reaches the CloudWatch query, so assert on the
     * search-start argument rather than trusting the plumbing. Without an override the window is the
     * 5-minute default; the shipped deployment-event config widens it because that signal is
     * emitted once at startup and cannot be recovered by retrying.
     */
    @Test
    public void lookbackWindowDefaultsToFiveMinutesAndHonoursOverride() throws Exception {
        long defaultStart = captureSearchStart(null);
        long widenedStart = captureSearchStart(30);
        long now = System.currentTimeMillis();

        long defaultMinutes = (now - defaultStart) / 60_000;
        long widenedMinutes = (now - widenedStart) / 60_000;

        assertTrue(
                defaultMinutes >= 4 && defaultMinutes <= 6,
                "expected ~5 minute default lookback, got " + defaultMinutes);
        assertTrue(
                widenedMinutes >= 29 && widenedMinutes <= 31,
                "expected ~30 minute overridden lookback, got " + widenedMinutes);
    }

    /** Runs one validation and returns the epoch-millis search start it asked CloudWatch for. */
    private long captureSearchStart(Integer lookbackMinutes) throws Exception {
        String fixture =
                IOUtils.toString(
                        new URL(TEMPLATE_ROOT + FIXTURE_ROOT + "deployment-event.json"),
                        Charset.defaultCharset());
        List<FilteredLogEvent> events =
                mapper.readValue(fixture, new TypeReference<List<FilteredLogEvent>>() {});

        CloudWatchService svc = Mockito.mock(CloudWatchService.class);
        ArgumentCaptor<Long> startTime = ArgumentCaptor.forClass(Long.class);
        when(svc.filterLogs(
                        Mockito.eq(LOG_GROUP), Mockito.anyString(), startTime.capture(), Mockito.anyInt()))
                .thenReturn(events);

        ValidationConfig validationConfig = new ValidationConfig();
        validationConfig.setCallingType("none");
        validationConfig.setValidationType("cw-log");
        validationConfig.setExpectedLogStructureTemplate("DOTNET_EC2_SERVICE_EVENTS_DEPLOYMENT_EVENT");
        validationConfig.setCwLogFilterPattern(
                "{ ($.resource.attributes.['service.name'] = \"{{serviceName}}\") }");
        validationConfig.setCwLogLookbackMinutes(lookbackMinutes);

        CWLogValidator validator = new CWLogValidator();
        validator.init(context, validationConfig, validationConfig.getExpectedLogStructureTemplate());
        validator.setMaxRetryCount(1);
        validator.setCloudWatchService(svc);
        validator.validate();

        return startTime.getValue();
    }

    private void validate(String templateEnumName, String fixtureSuffix) throws Exception {
        String fixture =
                IOUtils.toString(
                        new URL(TEMPLATE_ROOT + FIXTURE_ROOT + fixtureSuffix), Charset.defaultCharset());
        List<FilteredLogEvent> events =
                mapper.readValue(fixture, new TypeReference<List<FilteredLogEvent>>() {});

        when(cloudWatchService.filterLogs(
                        Mockito.eq(LOG_GROUP), Mockito.anyString(), Mockito.anyLong(), Mockito.anyInt()))
                .thenReturn(events);

        ValidationConfig validationConfig = new ValidationConfig();
        validationConfig.setCallingType("none");
        validationConfig.setValidationType("cw-log");
        // Set by enum name, exactly as the shipped validations/dotnet/ec2/service-events/*.yml do,
        // so this also covers the config-to-enum-to-resource wiring rather than just the template.
        validationConfig.setExpectedLogStructureTemplate(templateEnumName);
        // Any non-null pattern selects the custom-filter path in CWLogValidator; the pattern itself
        // is only handed to the mocked CloudWatchService, so its content is not under test here.
        validationConfig.setCwLogFilterPattern(
                "{ ($.resource.attributes.['service.name'] = \"{{serviceName}}\") }");

        CWLogValidator validator = new CWLogValidator();
        validator.init(context, validationConfig, validationConfig.getExpectedLogStructureTemplate());
        validator.setMaxRetryCount(1);
        validator.setCloudWatchService(cloudWatchService);
        validator.validate();
    }
}
