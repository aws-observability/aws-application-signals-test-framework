/*
 * Copyright Amazon.com, Inc. or its affiliates.
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

import com.amazon.aoc.enums.GenericConstants;
import com.amazon.aoc.exception.BaseException;
import com.amazon.aoc.exception.ExceptionCode;
import com.amazon.aoc.fileconfigs.FileConfig;
import com.amazon.aoc.helpers.MustacheHelper;
import com.amazon.aoc.helpers.RetryHelper;
import com.amazon.aoc.helpers.SortUtils;
import com.amazon.aoc.models.Context;
import com.amazon.aoc.models.SampleAppResponse;
import com.amazon.aoc.models.ValidationConfig;
import com.amazon.aoc.models.xray.Entity;
import com.amazon.aoc.services.XRayService;
import com.amazonaws.services.xray.model.Segment;
import com.amazonaws.services.xray.model.Trace;
import com.amazonaws.services.xray.model.TraceSummary;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.PropertyNamingStrategy;
import com.github.wnameless.json.flattener.JsonFlattener;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import com.github.wnameless.json.flattener.JsonifyArrayList;
import lombok.extern.log4j.Log4j2;

@Log4j2
public class TraceValidator implements IValidator {
  private MustacheHelper mustacheHelper = new MustacheHelper();
  private XRayService xrayService;
  private Context context;
  private ValidationConfig validationConfig;
  private FileConfig expectedTrace;
  private static final ObjectMapper MAPPER =
      new ObjectMapper().setPropertyNamingStrategy(PropertyNamingStrategy.SNAKE_CASE);
  private final int sampleAppRetryCount;
  private final int xRayRetryCount;

  public TraceValidator(XRayService xrayService, int sampleAppRetryCount, int xRayRetryCount) {
    this.xrayService = xrayService;
    this.sampleAppRetryCount = sampleAppRetryCount;
    this.xRayRetryCount = xRayRetryCount;
  }

  @Override
  public void init(
      Context context, ValidationConfig validationConfig, FileConfig expectedTrace)
      throws Exception {
    this.context = context;
    this.validationConfig = validationConfig;
    this.expectedTrace = expectedTrace;
  }

  @Override
  public void validate() throws Exception {
    log.info("Start Trace Validation for path {}", validationConfig.getHttpPath());

    Map<String, Object> storedTrace = this.getStoredTrace();
    log.info("value of stored trace map: {}", storedTrace);

    // 2 retries for calling the sample app to handle the Lambda case,
    // where first request might be a cold start and have an additional unexpected subsegment
    boolean isMatched =
        RetryHelper.retry(
            sampleAppRetryCount,
            Integer.parseInt(GenericConstants.SLEEP_IN_MILLISECONDS.getVal()),
            false,
            () -> {
             // Retry 5 times to since segments might not be immediately available in X-Ray service
              RetryHelper.retry(
                  xRayRetryCount,
                  () -> {
                    // get retrieved trace from x-ray service
                    Map<String, Object> retrievedTrace = this.getTrace();
                    log.info("value of retrieved trace map: {}", retrievedTrace);

                    // data model validation of other fields of segment document
                    for (Map.Entry<String, Object> entry : storedTrace.entrySet()) {
                      String targetKey = entry.getKey();
                      if (retrievedTrace.get(targetKey) == null) {
                        log.error("mis target data: {}", targetKey);
                        throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
                      }

                      String expected = entry.getValue().toString();
                      String actual = retrievedTrace.get(targetKey).toString();

                      Pattern pattern = Pattern.compile(expected.toString());
                      Matcher matcher = pattern.matcher(actual.toString());

                      if (!matcher.find()) {
                        log.error("data model validation failed");
                        log.info("mismatched data model field list");
                        log.info("value of stored trace map: {}", entry.getValue());
                        log.info("value of retrieved map: {}", retrievedTrace.get(targetKey));
                        log.info("==========================================");
                        throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
                      }
                    }
                  });
            });

    if (!isMatched) {
      throw new BaseException(ExceptionCode.DATA_MODEL_NOT_MATCHED);
    }

    log.info("validation is passed for path {}", validationConfig.getHttpPath());
  }

  // this method will hit get trace from x-ray service and get retrieved trace
  private Map<String, Object> getTrace() throws Exception {
    // Filter used to find the expected trace.
    // ServiceName will help identify trace specific to current e2e test as it contains the testing-id
    String traceFilter = String.format("annotation.aws_local_service = \"%s\"", context.getServiceName());

    // Looking for trace generated by /client-call is different from the others because the API call is made by the sample app internally,
    // and not through external callers
    if (validationConfig.getHttpPath().contains("client-call")) {
      traceFilter += " AND annotation.aws_local_service = \"local-root-client-call\"";
    } else {
      traceFilter += (String.format(" AND annotation.aws_local_operation = \"%s %s\"",
              validationConfig.getHttpMethod().toUpperCase(),
              validationConfig.getHttpPath()));
    }
    log.info("Trace Filter: {}", traceFilter);
    List<TraceSummary> retrieveTraceLists = xrayService.searchTraces(traceFilter);
    List<String> traceIdLists = Collections.singletonList(retrieveTraceLists.get(0).getId());
    List<Trace> retrievedTraceList = xrayService.listTraceByIds(traceIdLists);

    if (retrievedTraceList == null || retrievedTraceList.isEmpty()) {
      throw new BaseException(ExceptionCode.EMPTY_LIST);
    }
    return this.flattenDocument(retrievedTraceList.get(0).getSegments());
  }

  private Map<String, Object> flattenDocument(List<Segment> segmentList) {
    List<Entity> entityList = new ArrayList<>();

    // Parse retrieved segment documents into a barebones Entity POJO
    for (Segment segment : segmentList) {
      Entity entity;
      try {
        entity = MAPPER.readValue(segment.getDocument(), Entity.class);
        entityList.add(entity);
      } catch (JsonProcessingException e) {
        log.warn("Error parsing segment JSON", e);
      }
    }

    // Recursively sort all segments and subsegments so the ordering is always consistent
    SortUtils.recursiveEntitySort(entityList);
    StringBuilder segmentsJson = new StringBuilder("[");

    // build the segment's document as a json array and flatten it for easy comparison
    for (Entity entity : entityList) {
      try {
        segmentsJson.append(MAPPER.writeValueAsString(entity));
        segmentsJson.append(",");
      } catch (JsonProcessingException e) {
        log.warn("Error serializing segment JSON", e);
      }
    }

    segmentsJson.replace(segmentsJson.length() - 1, segmentsJson.length(), "]");
    return JsonFlattener.flattenAsMap(segmentsJson.toString());
  }

  // This method will get the stored traces
  private Map<String, Object> getStoredTrace() throws Exception {
    Map<String, Object> flattenedJsonMapForStoredTraces = null;

    String jsonExpectedTrace = mustacheHelper.render(this.expectedTrace, context);

    try {
      // flattened JSON object to a map
      flattenedJsonMapForStoredTraces = JsonFlattener.flattenAsMap(jsonExpectedTrace);
    } catch (Exception e) {
      e.printStackTrace();
    }

    return flattenedJsonMapForStoredTraces;
  }
}
