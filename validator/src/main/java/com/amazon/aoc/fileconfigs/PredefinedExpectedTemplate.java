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

package com.amazon.aoc.fileconfigs;

import java.net.URL;

/**
 * PredefinedExpectedTemplate includes all the built-in expected data templates, which are under
 * resources/expected-data-templates.
 */
public enum PredefinedExpectedTemplate implements FileConfig {
  /** EKS Test Case Validations */
  JAVA_EKS_OUTGOING_HTTP_CALL_LOG("/expected-data-template/java/eks/outgoing-http-call-log.mustache"),
  JAVA_EKS_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/java/eks/outgoing-http-call-metric.mustache"),
  JAVA_EKS_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/java/eks/outgoing-http-call-trace.mustache"),

  JAVA_EKS_AWS_SDK_CALL_LOG("/expected-data-template/java/eks/aws-sdk-call-log.mustache"),
  JAVA_EKS_AWS_SDK_CALL_METRIC("/expected-data-template/java/eks/aws-sdk-call-metric.mustache"),
  JAVA_EKS_AWS_SDK_CALL_TRACE("/expected-data-template/java/eks/aws-sdk-call-trace.mustache"),

  JAVA_EKS_REMOTE_SERVICE_LOG("/expected-data-template/java/eks/remote-service-log.mustache"),
  JAVA_EKS_REMOTE_SERVICE_METRIC("/expected-data-template/java/eks/remote-service-metric.mustache"),
  JAVA_EKS_REMOTE_SERVICE_TRACE("/expected-data-template/java/eks/remote-service-trace.mustache"),

  JAVA_EKS_CLIENT_CALL_LOG("/expected-data-template/java/eks/client-call-log.mustache"),
  JAVA_EKS_CLIENT_CALL_METRIC("/expected-data-template/java/eks/client-call-metric.mustache"),
  JAVA_EKS_CLIENT_CALL_TRACE("/expected-data-template/java/eks/client-call-trace.mustache"),

  /** Java EC2 Test Case Validations */
  JAVA_EC2_OUTGOING_HTTP_CALL_LOG("/expected-data-template/java/ec2/outgoing-http-call-log.mustache"),
  JAVA_EC2_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/java/ec2/outgoing-http-call-metric.mustache"),
  JAVA_EC2_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/java/ec2/outgoing-http-call-trace.mustache"),

  JAVA_EC2_AWS_SDK_CALL_LOG("/expected-data-template/java/ec2/aws-sdk-call-log.mustache"),
  JAVA_EC2_AWS_SDK_CALL_METRIC("/expected-data-template/java/ec2/aws-sdk-call-metric.mustache"),
  JAVA_EC2_AWS_SDK_CALL_TRACE("/expected-data-template/java/ec2/aws-sdk-call-trace.mustache"),

  JAVA_EC2_REMOTE_SERVICE_LOG("/expected-data-template/java/ec2/remote-service-log.mustache"),
  JAVA_EC2_REMOTE_SERVICE_METRIC("/expected-data-template/java/ec2/remote-service-metric.mustache"),
  JAVA_EC2_REMOTE_SERVICE_TRACE("/expected-data-template/java/ec2/remote-service-trace.mustache"),

  JAVA_EC2_CLIENT_CALL_LOG("/expected-data-template/java/ec2/client-call-log.mustache"),
  JAVA_EC2_CLIENT_CALL_METRIC("/expected-data-template/java/ec2/client-call-metric.mustache"),
  JAVA_EC2_CLIENT_CALL_TRACE("/expected-data-template/java/ec2/client-call-trace.mustache"),

 /** Python EKS Test Case Validations */
  PYTHON_EKS_OUTGOING_HTTP_CALL_LOG("/expected-data-template/python/eks/outgoing-http-call-log.mustache"),
  PYTHON_EKS_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/python/eks/outgoing-http-call-metric.mustache"),
  PYTHON_EKS_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/python/eks/outgoing-http-call-trace.mustache"),

  PYTHON_EKS_AWS_SDK_CALL_LOG("/expected-data-template/python/eks/aws-sdk-call-log.mustache"),
  PYTHON_EKS_AWS_SDK_CALL_METRIC("/expected-data-template/python/eks/aws-sdk-call-metric.mustache"),
  PYTHON_EKS_AWS_SDK_CALL_TRACE("/expected-data-template/python/eks/aws-sdk-call-trace.mustache"),

  PYTHON_EKS_REMOTE_SERVICE_LOG("/expected-data-template/python/eks/remote-service-log.mustache"),
  PYTHON_EKS_REMOTE_SERVICE_METRIC("/expected-data-template/python/eks/remote-service-metric.mustache"),
  PYTHON_EKS_REMOTE_SERVICE_TRACE("/expected-data-template/python/eks/remote-service-trace.mustache"),

  PYTHON_EKS_CLIENT_CALL_LOG("/expected-data-template/python/eks/client-call-log.mustache"),
  PYTHON_EKS_CLIENT_CALL_METRIC("/expected-data-template/python/eks/client-call-metric.mustache"),
  PYTHON_EKS_CLIENT_CALL_TRACE("/expected-data-template/python/eks/client-call-trace.mustache"),

  /** Python EC2 Test Case Validations */
  PYTHON_EC2_OUTGOING_HTTP_CALL_LOG("/expected-data-template/python/ec2/outgoing-http-call-log.mustache"),
  PYTHON_EC2_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/python/ec2/outgoing-http-call-metric.mustache"),
  PYTHON_EC2_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/python/ec2/outgoing-http-call-trace.mustache"),

  PYTHON_EC2_AWS_SDK_CALL_LOG("/expected-data-template/python/ec2/aws-sdk-call-log.mustache"),
  PYTHON_EC2_AWS_SDK_CALL_METRIC("/expected-data-template/python/ec2/aws-sdk-call-metric.mustache"),
  PYTHON_EC2_AWS_SDK_CALL_TRACE("/expected-data-template/python/ec2/aws-sdk-call-trace.mustache"),

  PYTHON_EC2_REMOTE_SERVICE_LOG("/expected-data-template/python/ec2/remote-service-log.mustache"),
  PYTHON_EC2_REMOTE_SERVICE_METRIC("/expected-data-template/python/ec2/remote-service-metric.mustache"),
  PYTHON_EC2_REMOTE_SERVICE_TRACE("/expected-data-template/python/ec2/remote-service-trace.mustache"),

  PYTHON_EC2_CLIENT_CALL_LOG("/expected-data-template/python/ec2/client-call-log.mustache"),
  PYTHON_EC2_CLIENT_CALL_METRIC("/expected-data-template/python/ec2/client-call-metric.mustache"),
  PYTHON_EC2_CLIENT_CALL_TRACE("/expected-data-template/python/ec2/client-call-trace.mustache"),
  ;

  private String path;

  PredefinedExpectedTemplate(String path) {
    this.path = path;
  }

  @Override
  public URL getPath() {
    return getClass().getResource(path);
  }
}
