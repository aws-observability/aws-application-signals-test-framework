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

package com.amazon.aoc.models;

import com.amazon.aoc.fileconfigs.FileConfig;
import com.amazon.aoc.fileconfigs.LocalPathExpectedTemplate;
import com.amazon.aoc.fileconfigs.PredefinedExpectedTemplate;
import com.amazonaws.util.StringUtils;
import lombok.Data;

@Data
public class ValidationConfig {
  String validationType;
  String callingType = "none";

  String httpPath;
  String httpMethod;
  String queryString;

  String expectedResultPath;
  Boolean shouldValidateMetricValue;

  String expectedMetricTemplate;
  String expectedTraceTemplate;
  String expectedLogStructureTemplate;
  String cwLogFilterPattern;

  /**
   * How far back a cw-log validation searches CloudWatch Logs, in minutes. Defaults to 5 when unset,
   * which suits signals the application re-emits continuously. Widen it for a one-shot signal, whose
   * single record would otherwise fall outside the window while the validator was still starting up
   * — no amount of retrying recovers it, because the window slides forward with the clock.
   */
  Integer cwLogLookbackMinutes;

  /** PromQL query template (mustache) for Service Events OTLP metric validation. */
  String promQlQuery;

  /** alarm related. */
  Integer pullingDuration;

  Integer pullingTimes;

  /** performance test related. */
  String cpuMetricName;

  String memoryMetricName;
  Integer collectionPeriod;
  Integer datapointPeriod;
  String dataType;
  String dataMode;
  Integer dataRate;
  String[] otReceivers;
  String[] otProcessors;
  String[] otExporters;

  // Dimensions
  String testcase;
  String commitId;
  String instanceId;
  String instanceType;
  String launchDate;
  String exe;
  String processName;
  String testingAmi;
  String negativeSoaking;

  public FileConfig getExpectedMetricTemplate() {
    return this.getTemplate(this.expectedMetricTemplate);
  }

  public FileConfig getExpectedTraceTemplate() {
    return this.getTemplate(this.expectedTraceTemplate);
  }

  public FileConfig getExpectedLogStructureTemplate() {
    return this.getTemplate(this.expectedLogStructureTemplate);
  }

  /**
   * get expected template 1. if the path starts with "file://", we assume it's a local path. 2. if
   * not, we assume it's a ENUM name which we defined in the framework.
   *
   * @return ExpectedMetric
   */
  private FileConfig getTemplate(String templatePath) {
    // allow templatePath to be empty or null
    // return a empty FileConfig in this case.
    if (StringUtils.isNullOrEmpty(templatePath)) {
      return new LocalPathExpectedTemplate(templatePath);
    }

    if (templatePath.startsWith("file://")) {
      return new LocalPathExpectedTemplate(templatePath);
    }

    return PredefinedExpectedTemplate.valueOf(templatePath);
  }
}
