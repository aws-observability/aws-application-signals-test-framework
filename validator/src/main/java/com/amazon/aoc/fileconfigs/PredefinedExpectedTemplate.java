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
  /** Java EKS Test Case Validations */
  EKS_OUTGOING_HTTP_CALL_LOG("/expected-data-template/eks/outgoing-http-call-log.mustache"),
  EKS_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/eks/outgoing-http-call-metric.mustache"),
  EKS_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/eks/outgoing-http-call-trace.mustache"),

  EKS_AWS_SDK_CALL_LOG("/expected-data-template/eks/aws-sdk-call-log.mustache"),
  EKS_AWS_SDK_CALL_METRIC("/expected-data-template/eks/aws-sdk-call-metric.mustache"),
  EKS_AWS_SDK_CALL_TRACE("/expected-data-template/eks/aws-sdk-call-trace.mustache"),

  EKS_REMOTE_SERVICE_LOG("/expected-data-template/eks/remote-service-log.mustache"),
  EKS_REMOTE_SERVICE_METRIC("/expected-data-template/eks/remote-service-metric.mustache"),
  EKS_REMOTE_SERVICE_TRACE("/expected-data-template/eks/remote-service-trace.mustache"),

  EKS_CLIENT_CALL_LOG("/expected-data-template/eks/client-call-log.mustache"),
  EKS_CLIENT_CALL_METRIC("/expected-data-template/eks/client-call-metric.mustache"),
  EKS_CLIENT_CALL_TRACE("/expected-data-template/eks/client-call-trace.mustache"),

  /** Java EC2 Test Case Validations */
  EC2_OUTGOING_HTTP_CALL_LOG("/expected-data-template/ec2/outgoing-http-call-log.mustache"),
  EC2_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/ec2/outgoing-http-call-metric.mustache"),
  EC2_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/ec2/outgoing-http-call-trace.mustache"),

  EC2_AWS_SDK_CALL_LOG("/expected-data-template/ec2/aws-sdk-call-log.mustache"),
  EC2_AWS_SDK_CALL_METRIC("/expected-data-template/ec2/aws-sdk-call-metric.mustache"),
  EC2_AWS_SDK_CALL_TRACE("/expected-data-template/ec2/aws-sdk-call-trace.mustache"),

  EC2_REMOTE_SERVICE_LOG("/expected-data-template/ec2/remote-service-log.mustache"),
  EC2_REMOTE_SERVICE_METRIC("/expected-data-template/ec2/remote-service-metric.mustache"),
  EC2_REMOTE_SERVICE_TRACE("/expected-data-template/ec2/remote-service-trace.mustache"),

  EC2_CLIENT_CALL_LOG("/expected-data-template/ec2/client-call-log.mustache"),
  EC2_CLIENT_CALL_METRIC("/expected-data-template/ec2/client-call-metric.mustache"),
  EC2_CLIENT_CALL_TRACE("/expected-data-template/ec2/client-call-trace.mustache"),

  /** Java EC2 Test Case Validations */
  K8S_OUTGOING_HTTP_CALL_LOG("/expected-data-template/k8s/outgoing-http-call-log.mustache"),
  K8S_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/k8s/outgoing-http-call-metric.mustache"),
  K8S_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/k8s/outgoing-http-call-trace.mustache"),

  K8S_AWS_SDK_CALL_LOG("/expected-data-template/k8s/aws-sdk-call-log.mustache"),
  K8S_AWS_SDK_CALL_METRIC("/expected-data-template/k8s/aws-sdk-call-metric.mustache"),
  K8S_AWS_SDK_CALL_TRACE("/expected-data-template/k8s/aws-sdk-call-trace.mustache"),

  K8S_REMOTE_SERVICE_LOG("/expected-data-template/k8s/remote-service-log.mustache"),
  K8S_REMOTE_SERVICE_METRIC("/expected-data-template/k8s/remote-service-metric.mustache"),
  K8S_REMOTE_SERVICE_TRACE("/expected-data-template/k8s/remote-service-trace.mustache"),

  K8S_CLIENT_CALL_LOG("/expected-data-template/k8s/client-call-log.mustache"),
  K8S_CLIENT_CALL_METRIC("/expected-data-template/k8s/client-call-metric.mustache"),
  K8S_CLIENT_CALL_TRACE("/expected-data-template/k8s/client-call-trace.mustache"),

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
