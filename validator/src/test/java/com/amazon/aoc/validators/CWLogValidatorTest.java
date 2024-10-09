package com.amazon.aoc.validators;

import com.amazon.aoc.models.Context;
import com.amazon.aoc.models.ValidationConfig;
import com.amazon.aoc.services.CloudWatchService;
import com.amazonaws.services.logs.model.FilteredLogEvent;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.json.JsonMapper;
import org.apache.commons.io.IOUtils;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.DisabledIf;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;

import java.net.URL;
import java.nio.charset.Charset;
import java.util.List;

import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@DisabledIf("isWindows")
public class CWLogValidatorTest extends ValidatorBaseTest {
    private Context context;
    @Mock
    private CloudWatchService cloudWatchService;

    private final ObjectMapper mapper = new ObjectMapper();

    static boolean isWindows() {
        return System.getProperty("os.name").toLowerCase().startsWith("win");
    }

    @BeforeEach
    public void setUp() throws Exception {
        context = initContext();
    }

    @Test
    public void testValidateRuntimeLogs() throws Exception {
        String file = IOUtils.toString(new URL(TEMPLATE_ROOT + "log/actual-runtime.json"), Charset.defaultCharset());
        List<FilteredLogEvent> result = mapper.readValue(file, new TypeReference<List<FilteredLogEvent>>() {
        });
        when(cloudWatchService.filterLogs(
                Mockito.eq("/aws/application-signals/data"),
                Mockito.eq("{ ($.Service = serviceName) && ($.RemoteService NOT EXISTS) && ($.RemoteOperation NOT EXISTS)&& ($.Operation NOT EXISTS) }"),
                Mockito.anyLong(),
                Mockito.anyInt()
        )).thenReturn(result);

        ValidationConfig validationConfig =
                initValidationConfig(TEMPLATE_ROOT + "log/expected-runtime.mustache");
        CWLogValidator cwLogValidator = new CWLogValidator();
        cwLogValidator.init(context, validationConfig, validationConfig.getExpectedLogStructureTemplate());
        cwLogValidator.setMaxRetryCount(1);
        cwLogValidator.setCloudWatchService(cloudWatchService);
        cwLogValidator.validate();
    }

    @Override
    protected ValidationConfig initValidationConfig(String metricTemplate) {
        ValidationConfig validationConfig = new ValidationConfig();
        validationConfig.setCallingType("none");
        validationConfig.setExpectedLogStructureTemplate(metricTemplate);
        return validationConfig;
    }

}
