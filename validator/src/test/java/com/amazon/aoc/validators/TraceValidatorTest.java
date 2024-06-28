package com.amazon.aoc.validators;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.mockito.Mockito.when;

import java.net.URL;
import java.nio.charset.Charset;
import java.util.List;

import com.amazon.aoc.callers.HttpCaller;
import com.amazon.aoc.models.ValidationConfig;
import com.amazon.aoc.services.XRayService;

import com.amazonaws.services.xray.model.Segment;
import com.amazonaws.services.xray.model.Trace;

import org.apache.commons.io.IOUtils;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
public class TraceValidatorTest extends ValidatorBaseTest {

    private static final String TRACE_ID = "1-00000000-000000000000000000000001";

    @Mock
    private XRayService xRayService;
    @Mock
    private Trace trace;
    @Mock
    private Segment segment;

    private TraceValidator traceValidator;
    private String DOCUMENT;

    @BeforeEach
    public void beforeEach() throws Exception {
        HttpCaller httpCaller = mockHttpCaller(TRACE_ID);
        ValidationConfig validationConfig = initValidationConfig(TEMPLATE_ROOT + "trace/expected/example-trace.mustache");
        traceValidator = new TraceValidator(xRayService, 1, 1);
        traceValidator.init(
                initContext(),
                validationConfig, httpCaller,
                validationConfig.getExpectedTraceTemplate()
        );
        DOCUMENT = IOUtils.toString(new URL(TEMPLATE_ROOT + "trace/actual/example-trace-document.json"), Charset.defaultCharset());
    }

    @Test
    public void testValidate() {
        when(xRayService.listTraceByIds(List.of(TRACE_ID))).thenReturn(List.of(trace));
        when(trace.getSegments()).thenReturn(List.of(segment));
        when(segment.getDocument()).thenReturn(DOCUMENT);

        assertDoesNotThrow(() -> traceValidator.validate());
    }
}
