package com.amazon.aoc.validators;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.amazon.aoc.models.Context;
import com.amazon.aoc.models.SampleAppResponse;
import com.amazon.aoc.models.ValidationConfig;

public class ValidatorBaseTest {
    protected static final String TEMPLATE_ROOT =
            "file://" + System.getProperty("user.dir") + "/src/test/test-resources/";
    private static final String SERVICE_NAME = "serviceName";
    private static final String REMOTE_SERVICE_NAME = "remoteServiceName";
    private static final String REMOTE_SERVICE_DEPLOYMENT_NAME = "remoteServiceDeploymentName";
    private static final String TESTING_ID = "testIdentifier";

    protected Context initContext() {
        // fake vars
        String testingId = "testingId";
        String region = "region";
        String namespace = "metricNamespace";

        // faked context
        Context context = new Context(testingId, region, false, false);
        context.setMetricNamespace(namespace);
        context.setServiceName(SERVICE_NAME);
        context.setRemoteServiceName(REMOTE_SERVICE_NAME);
        context.setRemoteServiceDeploymentName(REMOTE_SERVICE_DEPLOYMENT_NAME);
        context.setTestingId(TESTING_ID);
        return context;
    }

    protected ValidationConfig initValidationConfig(String traceTemplate) {
        ValidationConfig validationConfig = new ValidationConfig();
        validationConfig.setCallingType("http");
        validationConfig.setHttpMethod("get");
        validationConfig.setHttpPath("/aws-sdk-call");
        validationConfig.setExpectedTraceTemplate(traceTemplate);
        return validationConfig;
    }
}
