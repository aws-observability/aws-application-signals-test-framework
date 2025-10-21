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

import com.amazon.aoc.exception.BaseException;
import com.amazon.aoc.exception.ExceptionCode;
import com.amazon.aoc.fileconfigs.FileConfig;
import com.amazon.aoc.helpers.CWMetricHelper;
import com.amazon.aoc.helpers.RetryHelper;
import com.amazon.aoc.models.Context;
import com.amazon.aoc.models.ValidationConfig;
import com.amazon.aoc.services.CloudWatchService;
import com.amazonaws.services.cloudwatch.model.Dimension;
import com.amazonaws.services.cloudwatch.model.Metric;
import com.google.common.annotations.VisibleForTesting;
import com.google.common.collect.ImmutableSet;
import com.google.common.collect.Lists;
import lombok.extern.log4j.Log4j2;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Set;

@Log4j2
public class CWMetricValidator implements IValidator {
  private static final int DEFAULT_MAX_RETRY_COUNT = 100;
  private static final String ANY_VALUE = "ANY_VALUE";

  private Context context;
  private ValidationConfig validationConfig;
  private FileConfig expectedMetric;

  private CloudWatchService cloudWatchService;
  private CWMetricHelper cwMetricHelper;
  private int maxRetryCount;

  @VisibleForTesting
  public void setCloudWatchService(CloudWatchService cloudWatchService) {
    this.cloudWatchService = cloudWatchService;
  }

  @VisibleForTesting
  public void setMaxRetryCount(int maxRetryCount) {
    this.maxRetryCount = maxRetryCount;
  }

  @Override
  public void validate() throws Exception {
    log.info("Start Metric Validation for path {}", validationConfig.getHttpPath());
    // get expected metrics and remove the to be skipped dimensions
    final List<Metric> expectedMetricList =
        cwMetricHelper.listExpectedMetrics(context, expectedMetric);
    Set<String> skippedDimensionNameList = new HashSet<>();
    for (Metric metric : expectedMetricList) {
      for (Dimension dimension : metric.getDimensions()) {

        if (dimension.getValue() == null || dimension.getValue().equals("")) {
          continue;
        }

        if (dimension.getValue().equals("SKIP")) {
          skippedDimensionNameList.add(dimension.getName());
        }
      }
    }
    for (Metric metric : expectedMetricList) {
      metric
          .getDimensions()
          .removeIf((dimension) -> skippedDimensionNameList.contains(dimension.getName()));
    }

    // get metric from cloudwatch
    RetryHelper.retry(
        maxRetryCount,
        () -> {
          String httpPath = validationConfig.getHttpPath();
          // Special handling for Genesis path - just check if any metrics exists in namespace
          // since ADOT will just capture any OTel Metrics emitted from the instrumentation library used
          // and convert them into EMF metrics, it's impossible to create a validation template for this.
          if (httpPath != null && httpPath.contains("ai-chat")) {
            validateAnyMetricExists();
            return;
          }
          // We will query the Service, RemoteService, and RemoteTarget dimensions to ensure we
          // get all metrics from all aggregations, specifically the [RemoteService] aggregation.
          List<String> serviceNames =
              Lists.newArrayList(
                  context.getServiceName(), context.getRemoteServiceDeploymentName());
          List<String> remoteServiceNames =
              Lists.newArrayList(context.getRemoteServiceDeploymentName());
          List<String> remoteTargetNames = Lists.newArrayList();
          if (context.getRemoteServiceName() != null && !context.getRemoteServiceName().isEmpty()) {
            serviceNames.add(context.getRemoteServiceName());
          }
          if (context.getRemoteServiceIp() != null && !context.getRemoteServiceIp().isEmpty()) {
            remoteServiceNames.add(context.getRemoteServiceIp() + ":8080");
          }
          if (context.getTestingId() != null && !context.getTestingId().isEmpty()) {
            remoteTargetNames.add("::s3:::e2e-test-bucket-name-" + context.getTestingId());
          }

          List<Metric> actualMetricList = Lists.newArrayList();
          addMetrics(
              CloudWatchService.SERVICE_DIMENSION,
              serviceNames,
              expectedMetricList,
              actualMetricList);
          addMetrics(
              CloudWatchService.REMOTE_SERVICE_DIMENSION,
              remoteServiceNames,
              expectedMetricList,
              actualMetricList);
          addMetrics(
              CloudWatchService.REMOTE_TARGET_DIMENSION,
              remoteTargetNames,
              expectedMetricList,
              actualMetricList);
          addMetrics(
              CloudWatchService.CUSTOM_SERVICE_DIMENSION,
              serviceNames,
              expectedMetricList,
              actualMetricList);
          addMetrics(
              CloudWatchService.DEPLOYMENT_ENVIRONMENT_DIMENSION,
              Lists.newArrayList("ec2:default"),
              expectedMetricList,
              actualMetricList);

          // remove the skip dimensions
          log.info("dimensions to be skipped in validation: {}", skippedDimensionNameList);
          for (Metric metric : actualMetricList) {
            metric
                .getDimensions()
                .removeIf((dimension) -> skippedDimensionNameList.contains(dimension.getName()));
          }

          log.info("check if all the expected metrics are found");
          log.info("actual metricList is {}", actualMetricList);
          log.info("expected metricList is {}", expectedMetricList);
          compareMetricLists(expectedMetricList, actualMetricList);
        });

    log.info("validation is passed for path {}", validationConfig.getHttpPath());
  }

  private void addMetrics(
      String dimensionName,
      List<String> dimensionValues,
      List<Metric> expectedMetricList,
      List<Metric> actualMetricList)
      throws Exception {
    for (String dimensionValue : dimensionValues) {
      actualMetricList.addAll(
          this.listMetricFromCloudWatch(
              cloudWatchService, expectedMetricList, dimensionName, dimensionValue));
    }
  }

  /**
   * Check if every metric in expectedMetricList is in actualMetricList.
   *
   * @param expectedMetricList expectedMetricList
   * @param actualMetricList actualMetricList
   */
  private void compareMetricLists(List<Metric> expectedMetricList, List<Metric> actualMetricList)
      throws BaseException {

      Set<Metric> matchAny = new HashSet<>();
      Set<Metric> matchExact = new HashSet<>();
      for (Metric metric : expectedMetricList) {
          metric.getDimensions().sort(Comparator.comparing(Dimension::getName));
          if (metric.getDimensions().stream().anyMatch(d -> ANY_VALUE.equals(d.getValue()))) {
              matchAny.add(metric);
          } else {
              matchExact.add(metric);
          }
      }

      Set<Metric> actualMetricSet = new HashSet<>();
      for (Metric metric : actualMetricList) {
         metric.getDimensions().sort(Comparator.comparing(Dimension::getName));
         actualMetricSet.add(metric);
      }
      Set<Metric> actualMetricSnapshot = ImmutableSet.copyOf(actualMetricSet);

      actualMetricSet.removeAll(matchExact);
      matchExact.removeAll(actualMetricSnapshot);
      if (!matchExact.isEmpty())  {
          throw new BaseException(
                  ExceptionCode.EXPECTED_METRIC_NOT_FOUND,
                  String.format(
                          "metric in %ntoBeCheckedMetricList: %s is not found in %nbaseMetricList: %s %n",
                          matchExact.stream().findAny().get(), actualMetricSnapshot));
      }

      Iterator<Metric> iter = matchAny.iterator();
      while (iter.hasNext()) {
          Metric expected = iter.next();
          for (Metric actual : actualMetricSet) {
            if (metricEquals(expected, actual)) {
                iter.remove();
            }
          }
      }
     if (!matchAny.isEmpty()) {
         throw new BaseException(
                 ExceptionCode.EXPECTED_METRIC_NOT_FOUND,
                 String.format(
                         "metric in %ntoBeCheckedMetricList: %s is not found in %nbaseMetricList: %s %n",
                         matchAny.stream().findAny().get(), actualMetricSnapshot));
     }
  }
  
  private void validateAnyMetricExists() throws Exception {
    // This will grab all metrics from last 3 hours
    // See: https://docs.aws.amazon.com/AmazonCloudWatch/latest/APIReference/API_ListMetrics.html
    List<Metric> allMetricsInNamespace = cloudWatchService.listMetrics(context.getMetricNamespace(), null, null, null);
    log.info("Found {} metrics in namespace {}", allMetricsInNamespace.size(), context.getMetricNamespace());
    if (allMetricsInNamespace.isEmpty()) {
      throw new BaseException(ExceptionCode.EXPECTED_METRIC_NOT_FOUND, "No metrics found in namespace: " + context.getMetricNamespace());
    }
    log.info("validation is passed for path {}", validationConfig.getHttpPath());
  }

  private List<Metric> listMetricFromCloudWatch(
      CloudWatchService cloudWatchService,
      List<Metric> expectedMetricList,
      String dimensionKey,
      String dimensionValue)
      throws IOException {
    // put namespace into the map key, so that we can use it to search metric
    HashMap<String, String> metricNameMap = new HashMap<>();
    for (Metric metric : expectedMetricList) {
      metricNameMap.put(metric.getMetricName(), metric.getNamespace());
    }

    // search by metric name
    List<Metric> result = new ArrayList<>();
    for (String metricName : metricNameMap.keySet()) {
      result.addAll(
          cloudWatchService.listMetrics(
              metricNameMap.get(metricName), metricName, dimensionKey, dimensionValue));
    }
    return result;
  }

    private boolean metricEquals(Metric expected, Metric actual) {
        if (expected.getNamespace().equals(actual.getNamespace())
                && expected.getMetricName().equals(actual.getMetricName())) {
            if (expected.getDimensions().size() == actual.getDimensions().size()) {
                for (int i = 0; i < expected.getDimensions().size(); i++) {
                    if (!dimensionEquals(expected.getDimensions().get(i), actual.getDimensions().get(i))) {
                        return false;
                    }
                }
                return true;
            }
        }
        return false;
    }

    private boolean dimensionEquals(Dimension expected, Dimension actual) {
        if (expected.getName().equals(actual.getName())) {
            return ANY_VALUE.equals(expected.getValue()) ||
                    expected.getValue().equals(actual.getValue());
        }
        return false;
    }

  @Override
  public void init(
      Context context,
      ValidationConfig validationConfig,
      FileConfig expectedMetricTemplate)
      throws Exception {
    this.context = context;
    this.validationConfig = validationConfig;
    this.expectedMetric = expectedMetricTemplate;
    this.cloudWatchService = new CloudWatchService(context.getRegion());
    this.cwMetricHelper = new CWMetricHelper();
    this.maxRetryCount = DEFAULT_MAX_RETRY_COUNT;
  }
}
