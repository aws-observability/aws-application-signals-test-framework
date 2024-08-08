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
  /** JAVA EKS Test Case Validations */
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

  JAVA_EKS_RDS_MYSQL_LOG("/expected-data-template/java/eks/rds-mysql-log.mustache"),
  JAVA_EKS_RDS_MYSQL_METRIC("/expected-data-template/java/eks/rds-mysql-metric.mustache"),
  JAVA_EKS_RDS_MYSQL_TRACE("/expected-data-template/java/eks/rds-mysql-trace.mustache"),

  /** Java EC2 Default Test Case Validations */
  JAVA_EC2_DEFAULT_OUTGOING_HTTP_CALL_LOG("/expected-data-template/java/ec2/default/outgoing-http-call-log.mustache"),
  JAVA_EC2_DEFAULT_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/java/ec2/default/outgoing-http-call-metric.mustache"),
  JAVA_EC2_DEFAULT_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/java/ec2/default/outgoing-http-call-trace.mustache"),

  JAVA_EC2_DEFAULT_AWS_SDK_CALL_LOG("/expected-data-template/java/ec2/default/aws-sdk-call-log.mustache"),
  JAVA_EC2_DEFAULT_AWS_SDK_CALL_METRIC("/expected-data-template/java/ec2/default/aws-sdk-call-metric.mustache"),
  JAVA_EC2_DEFAULT_AWS_SDK_CALL_TRACE("/expected-data-template/java/ec2/default/aws-sdk-call-trace.mustache"),

  JAVA_EC2_DEFAULT_REMOTE_SERVICE_LOG("/expected-data-template/java/ec2/default/remote-service-log.mustache"),
  JAVA_EC2_DEFAULT_REMOTE_SERVICE_METRIC("/expected-data-template/java/ec2/default/remote-service-metric.mustache"),
  JAVA_EC2_DEFAULT_REMOTE_SERVICE_TRACE("/expected-data-template/java/ec2/default/remote-service-trace.mustache"),

  JAVA_EC2_DEFAULT_CLIENT_CALL_LOG("/expected-data-template/java/ec2/default/client-call-log.mustache"),
  JAVA_EC2_DEFAULT_CLIENT_CALL_METRIC("/expected-data-template/java/ec2/default/client-call-metric.mustache"),
  JAVA_EC2_DEFAULT_CLIENT_CALL_TRACE("/expected-data-template/java/ec2/default/client-call-trace.mustache"),

  /** Java EC2 ASG Test Case Validations */
  JAVA_EC2_ASG_OUTGOING_HTTP_CALL_LOG("/expected-data-template/java/ec2/asg/outgoing-http-call-log.mustache"),
  JAVA_EC2_ASG_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/java/ec2/asg/outgoing-http-call-metric.mustache"),
  JAVA_EC2_ASG_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/java/ec2/asg/outgoing-http-call-trace.mustache"),

  JAVA_EC2_ASG_AWS_SDK_CALL_LOG("/expected-data-template/java/ec2/asg/aws-sdk-call-log.mustache"),
  JAVA_EC2_ASG_AWS_SDK_CALL_METRIC("/expected-data-template/java/ec2/asg/aws-sdk-call-metric.mustache"),
  JAVA_EC2_ASG_AWS_SDK_CALL_TRACE("/expected-data-template/java/ec2/asg/aws-sdk-call-trace.mustache"),

  JAVA_EC2_ASG_REMOTE_SERVICE_LOG("/expected-data-template/java/ec2/asg/remote-service-log.mustache"),
  JAVA_EC2_ASG_REMOTE_SERVICE_METRIC("/expected-data-template/java/ec2/asg/remote-service-metric.mustache"),
  JAVA_EC2_ASG_REMOTE_SERVICE_TRACE("/expected-data-template/java/ec2/asg/remote-service-trace.mustache"),

  JAVA_EC2_ASG_CLIENT_CALL_LOG("/expected-data-template/java/ec2/asg/client-call-log.mustache"),
  JAVA_EC2_ASG_CLIENT_CALL_METRIC("/expected-data-template/java/ec2/asg/client-call-metric.mustache"),
  JAVA_EC2_ASG_CLIENT_CALL_TRACE("/expected-data-template/java/ec2/asg/client-call-trace.mustache"),

  /** Java EC2 K8s Test Case Validations */
  JAVA_K8S_OUTGOING_HTTP_CALL_LOG("/expected-data-template/java/k8s/outgoing-http-call-log.mustache"),
  JAVA_K8S_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/java/k8s/outgoing-http-call-metric.mustache"),
  JAVA_K8S_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/java/k8s/outgoing-http-call-trace.mustache"),

  JAVA_K8S_AWS_SDK_CALL_LOG("/expected-data-template/java/k8s/aws-sdk-call-log.mustache"),
  JAVA_K8S_AWS_SDK_CALL_METRIC("/expected-data-template/java/k8s/aws-sdk-call-metric.mustache"),
  JAVA_K8S_AWS_SDK_CALL_TRACE("/expected-data-template/java/k8s/aws-sdk-call-trace.mustache"),

  JAVA_K8S_REMOTE_SERVICE_LOG("/expected-data-template/java/k8s/remote-service-log.mustache"),
  JAVA_K8S_REMOTE_SERVICE_METRIC("/expected-data-template/java/k8s/remote-service-metric.mustache"),
  JAVA_K8S_REMOTE_SERVICE_TRACE("/expected-data-template/java/k8s/remote-service-trace.mustache"),

  JAVA_K8S_CLIENT_CALL_LOG("/expected-data-template/java/k8s/client-call-log.mustache"),
  JAVA_K8S_CLIENT_CALL_METRIC("/expected-data-template/java/k8s/client-call-metric.mustache"),
  JAVA_K8S_CLIENT_CALL_TRACE("/expected-data-template/java/k8s/client-call-trace.mustache"),

  /** Metric Limiter Test Case Validations */
  JAVA_METRIC_LIMITER_METRIC("/expected-data-template/java/metric_limiter/metric-limiter-metric.mustache"),

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

  PYTHON_EKS_RDS_MYSQL_LOG("/expected-data-template/python/eks/rds-mysql-log.mustache"),
  PYTHON_EKS_RDS_MYSQL_METRIC("/expected-data-template/python/eks/rds-mysql-metric.mustache"),
  PYTHON_EKS_RDS_MYSQL_TRACE("/expected-data-template/python/eks/rds-mysql-trace.mustache"),

  /** Python EC2 Default Test Case Validations */
  PYTHON_EC2_DEFAULT_OUTGOING_HTTP_CALL_LOG("/expected-data-template/python/ec2/default/outgoing-http-call-log.mustache"),
  PYTHON_EC2_DEFAULT_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/python/ec2/default/outgoing-http-call-metric.mustache"),
  PYTHON_EC2_DEFAULT_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/python/ec2/default/outgoing-http-call-trace.mustache"),

  PYTHON_EC2_DEFAULT_AWS_SDK_CALL_LOG("/expected-data-template/python/ec2/default/aws-sdk-call-log.mustache"),
  PYTHON_EC2_DEFAULT_AWS_SDK_CALL_METRIC("/expected-data-template/python/ec2/default/aws-sdk-call-metric.mustache"),
  PYTHON_EC2_DEFAULT_AWS_SDK_CALL_TRACE("/expected-data-template/python/ec2/default/aws-sdk-call-trace.mustache"),

  PYTHON_EC2_DEFAULT_REMOTE_SERVICE_LOG("/expected-data-template/python/ec2/default/remote-service-log.mustache"),
  PYTHON_EC2_DEFAULT_REMOTE_SERVICE_METRIC("/expected-data-template/python/ec2/default/remote-service-metric.mustache"),
  PYTHON_EC2_DEFAULT_REMOTE_SERVICE_TRACE("/expected-data-template/python/ec2/default/remote-service-trace.mustache"),

  PYTHON_EC2_DEFAULT_CLIENT_CALL_LOG("/expected-data-template/python/ec2/default/client-call-log.mustache"),
  PYTHON_EC2_DEFAULT_CLIENT_CALL_METRIC("/expected-data-template/python/ec2/default/client-call-metric.mustache"),
  PYTHON_EC2_DEFAULT_CLIENT_CALL_TRACE("/expected-data-template/python/ec2/default/client-call-trace.mustache"), 
    
  /** Python EC2 Asg Test Case Validations */
  PYTHON_EC2_ASG_OUTGOING_HTTP_CALL_LOG("/expected-data-template/python/ec2/asg/outgoing-http-call-log.mustache"),
  PYTHON_EC2_ASG_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/python/ec2/asg/outgoing-http-call-metric.mustache"),
  PYTHON_EC2_ASG_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/python/ec2/asg/outgoing-http-call-trace.mustache"),

  PYTHON_EC2_ASG_AWS_SDK_CALL_LOG("/expected-data-template/python/ec2/asg/aws-sdk-call-log.mustache"),
  PYTHON_EC2_ASG_AWS_SDK_CALL_METRIC("/expected-data-template/python/ec2/asg/aws-sdk-call-metric.mustache"),
  PYTHON_EC2_ASG_AWS_SDK_CALL_TRACE("/expected-data-template/python/ec2/asg/aws-sdk-call-trace.mustache"),

  PYTHON_EC2_ASG_REMOTE_SERVICE_LOG("/expected-data-template/python/ec2/asg/remote-service-log.mustache"),
  PYTHON_EC2_ASG_REMOTE_SERVICE_METRIC("/expected-data-template/python/ec2/asg/remote-service-metric.mustache"),
  PYTHON_EC2_ASG_REMOTE_SERVICE_TRACE("/expected-data-template/python/ec2/asg/remote-service-trace.mustache"),

  PYTHON_EC2_ASG_CLIENT_CALL_LOG("/expected-data-template/python/ec2/asg/client-call-log.mustache"),
  PYTHON_EC2_ASG_CLIENT_CALL_METRIC("/expected-data-template/python/ec2/asg/client-call-metric.mustache"),
  PYTHON_EC2_ASG_CLIENT_CALL_TRACE("/expected-data-template/python/ec2/asg/client-call-trace.mustache"),

  /** Python K8S Test Case Validations */
  PYTHON_K8S_OUTGOING_HTTP_CALL_LOG("/expected-data-template/python/k8s/outgoing-http-call-log.mustache"),
  PYTHON_K8S_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/python/k8s/outgoing-http-call-metric.mustache"),
  PYTHON_K8S_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/python/k8s/outgoing-http-call-trace.mustache"),

  PYTHON_K8S_AWS_SDK_CALL_LOG("/expected-data-template/python/k8s/aws-sdk-call-log.mustache"),
  PYTHON_K8S_AWS_SDK_CALL_METRIC("/expected-data-template/python/k8s/aws-sdk-call-metric.mustache"),
  PYTHON_K8S_AWS_SDK_CALL_TRACE("/expected-data-template/python/k8s/aws-sdk-call-trace.mustache"),

  PYTHON_K8S_REMOTE_SERVICE_LOG("/expected-data-template/python/k8s/remote-service-log.mustache"),
  PYTHON_K8S_REMOTE_SERVICE_METRIC("/expected-data-template/python/k8s/remote-service-metric.mustache"),
  PYTHON_K8S_REMOTE_SERVICE_TRACE("/expected-data-template/python/k8s/remote-service-trace.mustache"),

  PYTHON_K8S_CLIENT_CALL_LOG("/expected-data-template/python/k8s/client-call-log.mustache"),
  PYTHON_K8S_CLIENT_CALL_METRIC("/expected-data-template/python/k8s/client-call-metric.mustache"),
  PYTHON_K8S_CLIENT_CALL_TRACE("/expected-data-template/python/k8s/client-call-trace.mustache"),
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
