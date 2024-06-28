package com.amazon.aoc.validators;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.amazon.aoc.callers.HttpCaller;
import com.amazon.aoc.models.Context;
import com.amazon.aoc.models.SampleAppResponse;
import com.amazon.aoc.models.ValidationConfig;

public class ValidatorBaseTest {
    private static final String SERVICE_DIMENSION = "Service";
    private static final String REMOTE_SERVICE_DIMENSION = "RemoteService";
    private static final String REMOTE_TARGET_DIMENSION = "RemoteTarget";
    protected static final String TEMPLATE_ROOT =
            "file://" + System.getProperty("user.dir") + "/src/test/test-resources/";
    private static final String SERVICE_NAME = "serviceName";
    private static final String REMOTE_SERVICE_NAME = "remoteServiceName";
    private static final String REMOTE_SERVICE_DEPLOYMENT_NAME = "remoteServiceDeploymentName";
    private static final String TESTING_ID = "testIdentifier";

    protected HttpCaller mockHttpCaller(String traceId) throws Exception {
        HttpCaller httpCaller = mock(HttpCaller.class);
        SampleAppResponse sampleAppResponse = new SampleAppResponse();
        sampleAppResponse.setTraceId(traceId);
        when(httpCaller.callSampleApp()).thenReturn(sampleAppResponse);
        return httpCaller;
    }

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
        validationConfig.setExpectedTraceTemplate(traceTemplate);
        return validationConfig;
    }
}
