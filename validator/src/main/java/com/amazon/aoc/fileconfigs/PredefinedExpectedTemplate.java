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
 * PredefinedExpectedTemplate includes all the built-in expected data templates,
 * which are under resources/expected-data-templates.
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

  /** JAVA EKS Test Case Validations */
  JAVA_EKS_OTLP_OCB_OUTGOING_HTTP_CALL_LOG("/expected-data-template/java/eks-otlp-ocb/outgoing-http-call-log.mustache"),
  JAVA_EKS_OTLP_OCB_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/java/eks-otlp-ocb/outgoing-http-call-metric.mustache"),
  JAVA_EKS_OTLP_OCB_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/java/eks-otlp-ocb/outgoing-http-call-trace.mustache"),

  JAVA_EKS_OTLP_OCB_AWS_SDK_CALL_LOG("/expected-data-template/java/eks-otlp-ocb/aws-sdk-call-log.mustache"),
  JAVA_EKS_OTLP_OCB_AWS_SDK_CALL_METRIC("/expected-data-template/java/eks-otlp-ocb/aws-sdk-call-metric.mustache"),
  JAVA_EKS_OTLP_OCB_AWS_SDK_CALL_TRACE("/expected-data-template/java/eks-otlp-ocb/aws-sdk-call-trace.mustache"),

  JAVA_EKS_OTLP_OCB_REMOTE_SERVICE_LOG("/expected-data-template/java/eks-otlp-ocb/remote-service-log.mustache"),
  JAVA_EKS_OTLP_OCB_REMOTE_SERVICE_METRIC("/expected-data-template/java/eks-otlp-ocb/remote-service-metric.mustache"),
  JAVA_EKS_OTLP_OCB_REMOTE_SERVICE_TRACE("/expected-data-template/java/eks-otlp-ocb/remote-service-trace.mustache"),

  JAVA_EKS_OTLP_OCB_CLIENT_CALL_LOG("/expected-data-template/java/eks-otlp-ocb/client-call-log.mustache"),
  JAVA_EKS_OTLP_OCB_CLIENT_CALL_METRIC("/expected-data-template/java/eks-otlp-ocb/client-call-metric.mustache"),
  JAVA_EKS_OTLP_OCB_CLIENT_CALL_TRACE("/expected-data-template/java/eks-otlp-ocb/client-call-trace.mustache"),

  /** Java EC2 Default Test Case Validations */
  JAVA_EC2_DEFAULT_OUTGOING_HTTP_CALL_LOG("/expected-data-template/java/ec2/default/outgoing-http-call-log.mustache"),
  JAVA_EC2_DEFAULT_OUTGOING_HTTP_CALL_METRIC(
      "/expected-data-template/java/ec2/default/outgoing-http-call-metric.mustache"),
  JAVA_EC2_DEFAULT_OUTGOING_HTTP_CALL_TRACE(
      "/expected-data-template/java/ec2/default/outgoing-http-call-trace.mustache"),

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

  /** Java EC2 Ubuntu Test Case Validations */
  JAVA_EC2_UBUNTU_OUTGOING_HTTP_CALL_LOG("/expected-data-template/java/ec2/ubuntu/outgoing-http-call-log.mustache"),
  JAVA_EC2_UBUNTU_OUTGOING_HTTP_CALL_METRIC(
      "/expected-data-template/java/ec2/ubuntu/outgoing-http-call-metric.mustache"),
  JAVA_EC2_UBUNTU_OUTGOING_HTTP_CALL_TRACE(
      "/expected-data-template/java/ec2/ubuntu/outgoing-http-call-trace.mustache"),

  JAVA_EC2_UBUNTU_AWS_SDK_CALL_LOG("/expected-data-template/java/ec2/ubuntu/aws-sdk-call-log.mustache"),
  JAVA_EC2_UBUNTU_AWS_SDK_CALL_METRIC("/expected-data-template/java/ec2/ubuntu/aws-sdk-call-metric.mustache"),
  JAVA_EC2_UBUNTU_AWS_SDK_CALL_TRACE("/expected-data-template/java/ec2/ubuntu/aws-sdk-call-trace.mustache"),

  JAVA_EC2_UBUNTU_REMOTE_SERVICE_LOG("/expected-data-template/java/ec2/ubuntu/remote-service-log.mustache"),
  JAVA_EC2_UBUNTU_REMOTE_SERVICE_METRIC("/expected-data-template/java/ec2/ubuntu/remote-service-metric.mustache"),
  JAVA_EC2_UBUNTU_REMOTE_SERVICE_TRACE("/expected-data-template/java/ec2/ubuntu/remote-service-trace.mustache"),

  JAVA_EC2_UBUNTU_CLIENT_CALL_LOG("/expected-data-template/java/ec2/ubuntu/client-call-log.mustache"),
  JAVA_EC2_UBUNTU_CLIENT_CALL_METRIC("/expected-data-template/java/ec2/ubuntu/client-call-metric.mustache"),
  JAVA_EC2_UBUNTU_CLIENT_CALL_TRACE("/expected-data-template/java/ec2/ubuntu/client-call-trace.mustache"),

  /** Java EC2 ADOT SigV4 (ADOT Stand-Alone) Test Case Validations */
  JAVA_EC2_ADOT_SIGV4_OUTGOING_HTTP_CALL_LOG("/expected-data-template/java/ec2/adot-aws-otlp/outgoing-http-call-log.mustache"),
  JAVA_EC2_ADOT_SIGV4_OUTGOING_HTTP_CALL_METRIC(
      "/expected-data-template/java/ec2/adot-aws-otlp/outgoing-http-call-metric.mustache"),
  JAVA_EC2_ADOT_SIGV4_OUTGOING_HTTP_CALL_TRACE(
      "/expected-data-template/java/ec2/adot-aws-otlp/outgoing-http-call-trace.mustache"),

  JAVA_EC2_ADOT_SIGV4_AWS_SDK_CALL_LOG("/expected-data-template/java/ec2/adot-aws-otlp/aws-sdk-call-log.mustache"),
  JAVA_EC2_ADOT_SIGV4_AWS_SDK_CALL_METRIC("/expected-data-template/java/ec2/adot-aws-otlp/aws-sdk-call-metric.mustache"),
  JAVA_EC2_ADOT_SIGV4_AWS_SDK_CALL_TRACE("/expected-data-template/java/ec2/adot-aws-otlp/aws-sdk-call-trace.mustache"),

  JAVA_EC2_ADOT_SIGV4_REMOTE_SERVICE_LOG("/expected-data-template/java/ec2/adot-aws-otlp/remote-service-log.mustache"),
  JAVA_EC2_ADOT_SIGV4_REMOTE_SERVICE_METRIC("/expected-data-template/java/ec2/adot-aws-otlp/remote-service-metric.mustache"),
  JAVA_EC2_ADOT_SIGV4_REMOTE_SERVICE_TRACE("/expected-data-template/java/ec2/adot-aws-otlp/remote-service-trace.mustache"),

  JAVA_EC2_ADOT_SIGV4_CLIENT_CALL_LOG("/expected-data-template/java/ec2/adot-aws-otlp/client-call-log.mustache"),
  JAVA_EC2_ADOT_SIGV4_CLIENT_CALL_METRIC("/expected-data-template/java/ec2/adot-aws-otlp/client-call-metric.mustache"),
  JAVA_EC2_ADOT_SIGV4_CLIENT_CALL_TRACE("/expected-data-template/java/ec2/adot-aws-otlp/client-call-trace.mustache"),

  /** Java EC2 ADOT SigV4 Log Exporter Test Case Validation */
  JAVA_EC2_ADOT_OTLP_LOG("/expected-data-template/java/ec2/adot-aws-otlp/application-log.mustache"),

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

  /** Java ECS Test Case Validations */
  JAVA_ECS_HC_CALL_LOG("/expected-data-template/java/ecs/hc-log.mustache"),
  JAVA_ECS_HC_CALL_METRIC("/expected-data-template/java/ecs/hc-metric.mustache"),
  JAVA_ECS_HC_CALL_TRACE("/expected-data-template/java/ecs/hc-trace.mustache"),

  /** Metric Limiter Test Case Validations */
  JAVA_METRIC_LIMITER_METRIC("/expected-data-template/java/metric_limiter/metric-limiter-metric.mustache"),

  JAVA_RUNTIME_METRIC_LOG("/expected-data-template/java/runtime/runtime-log.mustache"),
  JAVA_RUNTIME_METRIC("/expected-data-template/java/runtime/runtime-metric.mustache"),

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
  PYTHON_EC2_DEFAULT_OUTGOING_HTTP_CALL_LOG(
      "/expected-data-template/python/ec2/default/outgoing-http-call-log.mustache"),
  PYTHON_EC2_DEFAULT_OUTGOING_HTTP_CALL_METRIC(
      "/expected-data-template/python/ec2/default/outgoing-http-call-metric.mustache"),
  PYTHON_EC2_DEFAULT_OUTGOING_HTTP_CALL_TRACE(
      "/expected-data-template/python/ec2/default/outgoing-http-call-trace.mustache"),

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

  /** Python EC2 ADOT SigV4 (Stand Alone ADOT) Test Case Validations */
  PYTHON_EC2_ADOT_SIGV4_OUTGOING_HTTP_CALL_LOG(
      "/expected-data-template/python/ec2/adot-aws-otlp/outgoing-http-call-log.mustache"),
  PYTHON_EC2_ADOT_SIGV4_OUTGOING_HTTP_CALL_METRIC(
      "/expected-data-template/python/ec2/adot-aws-otlp/outgoing-http-call-metric.mustache"),
  PYTHON_EC2_ADOT_SIGV4_OUTGOING_HTTP_CALL_TRACE(
      "/expected-data-template/python/ec2/adot-aws-otlp/outgoing-http-call-trace.mustache"),

  PYTHON_EC2_ADOT_SIGV4_AWS_SDK_CALL_LOG("/expected-data-template/python/ec2/adot-aws-otlp/aws-sdk-call-log.mustache"),
  PYTHON_EC2_ADOT_SIGV4_AWS_SDK_CALL_METRIC("/expected-data-template/python/ec2/adot-aws-otlp/aws-sdk-call-metric.mustache"),
  PYTHON_EC2_ADOT_SIGV4_AWS_SDK_CALL_TRACE("/expected-data-template/python/ec2/adot-aws-otlp/aws-sdk-call-trace.mustache"),

  PYTHON_EC2_ADOT_SIGV4_REMOTE_SERVICE_LOG("/expected-data-template/python/ec2/adot-aws-otlp/remote-service-log.mustache"),
  PYTHON_EC2_ADOT_SIGV4_REMOTE_SERVICE_METRIC("/expected-data-template/python/ec2/adot-aws-otlp/remote-service-metric.mustache"),
  PYTHON_EC2_ADOT_SIGV4_REMOTE_SERVICE_TRACE("/expected-data-template/python/ec2/adot-aws-otlp/remote-service-trace.mustache"),

  PYTHON_EC2_ADOT_SIGV4_CLIENT_CALL_LOG("/expected-data-template/python/ec2/adot-aws-otlp/client-call-log.mustache"),
  PYTHON_EC2_ADOT_SIGV4_CLIENT_CALL_METRIC("/expected-data-template/python/ec2/adot-aws-otlp/client-call-metric.mustache"),
  PYTHON_EC2_ADOT_SIGV4_CLIENT_CALL_TRACE("/expected-data-template/python/ec2/adot-aws-otlp/client-call-trace.mustache"),

  /** Python EC2 ADOT SigV4 Log Exporter Test Case Validation */
  PYTHON_EC2_ADOT_OTLP_LOG("/expected-data-template/python/ec2/adot-aws-otlp/application-log.mustache"),

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

  /** Python ECS Test Case Validations */
  PYTHON_ECS_HC_CALL_LOG("/expected-data-template/python/ecs/hc-log.mustache"),
  PYTHON_ECS_HC_CALL_METRIC("/expected-data-template/python/ecs/hc-metric.mustache"),
  PYTHON_ECS_HC_CALL_TRACE("/expected-data-template/python/ecs/hc-trace.mustache"),

  PYTHON_RUNTIME_METRIC_LOG("/expected-data-template/python/runtime/runtime-log.mustache"),
  PYTHON_RUNTIME_METRIC("/expected-data-template/python/runtime/runtime-metric.mustache"),

  /** DotNet EC2 Default Test Case Validations */
  DOTNET_EC2_DEFAULT_OUTGOING_HTTP_CALL_LOG(
      "/expected-data-template/dotnet/ec2/default/outgoing-http-call-log.mustache"),
  DOTNET_EC2_DEFAULT_OUTGOING_HTTP_CALL_METRIC(
      "/expected-data-template/dotnet/ec2/default/outgoing-http-call-metric.mustache"),
  DOTNET_EC2_DEFAULT_OUTGOING_HTTP_CALL_TRACE(
      "/expected-data-template/dotnet/ec2/default/outgoing-http-call-trace.mustache"),

  DOTNET_EC2_DEFAULT_AWS_SDK_CALL_LOG("/expected-data-template/dotnet/ec2/default/aws-sdk-call-log.mustache"),
  DOTNET_EC2_DEFAULT_AWS_SDK_CALL_METRIC("/expected-data-template/dotnet/ec2/default/aws-sdk-call-metric.mustache"),
  DOTNET_EC2_DEFAULT_AWS_SDK_CALL_TRACE("/expected-data-template/dotnet/ec2/default/aws-sdk-call-trace.mustache"),

  DOTNET_EC2_DEFAULT_REMOTE_SERVICE_LOG("/expected-data-template/dotnet/ec2/default/remote-service-log.mustache"),
  DOTNET_EC2_DEFAULT_REMOTE_SERVICE_METRIC("/expected-data-template/dotnet/ec2/default/remote-service-metric.mustache"),
  DOTNET_EC2_DEFAULT_REMOTE_SERVICE_TRACE("/expected-data-template/dotnet/ec2/default/remote-service-trace.mustache"),

  DOTNET_EC2_DEFAULT_CLIENT_CALL_LOG("/expected-data-template/dotnet/ec2/default/client-call-log.mustache"),
  DOTNET_EC2_DEFAULT_CLIENT_CALL_METRIC("/expected-data-template/dotnet/ec2/default/client-call-metric.mustache"),
  DOTNET_EC2_DEFAULT_CLIENT_CALL_TRACE("/expected-data-template/dotnet/ec2/default/client-call-trace.mustache"),

  /** DotNet EC2 Windows Default Test Case Validations */
  DOTNET_EC2_WINDOWS_DEFAULT_OUTGOING_HTTP_CALL_LOG(
          "/expected-data-template/dotnet/ec2/windows/outgoing-http-call-log.mustache"),
  DOTNET_EC2_WINDOWS_DEFAULT_OUTGOING_HTTP_CALL_METRIC(
          "/expected-data-template/dotnet/ec2/windows/outgoing-http-call-metric.mustache"),
  DOTNET_EC2_WINDOWS_DEFAULT_OUTGOING_HTTP_CALL_TRACE(
          "/expected-data-template/dotnet/ec2/windows/outgoing-http-call-trace.mustache"),

  DOTNET_EC2_WINDOWS_DEFAULT_AWS_SDK_CALL_LOG("/expected-data-template/dotnet/ec2/windows/aws-sdk-call-log.mustache"),
  DOTNET_EC2_WINDOWS_DEFAULT_AWS_SDK_CALL_METRIC("/expected-data-template/dotnet/ec2/windows/aws-sdk-call-metric.mustache"),
  DOTNET_EC2_WINDOWS_DEFAULT_AWS_SDK_CALL_TRACE("/expected-data-template/dotnet/ec2/windows/aws-sdk-call-trace.mustache"),

  DOTNET_EC2_WINDOWS_DEFAULT_REMOTE_SERVICE_LOG("/expected-data-template/dotnet/ec2/windows/remote-service-log.mustache"),
  DOTNET_EC2_WINDOWS_DEFAULT_REMOTE_SERVICE_METRIC("/expected-data-template/dotnet/ec2/windows/remote-service-metric.mustache"),
//  Because of a time sync issue, block the remote service trace check for now
//  DOTNET_EC2_WINDOWS_DEFAULT_REMOTE_SERVICE_TRACE("/expected-data-template/dotnet/ec2/windows/remote-service-trace.mustache"),

  DOTNET_EC2_WINDOWS_DEFAULT_CLIENT_CALL_LOG("/expected-data-template/dotnet/ec2/windows/client-call-log.mustache"),
  DOTNET_EC2_WINDOWS_DEFAULT_CLIENT_CALL_METRIC("/expected-data-template/dotnet/ec2/windows/client-call-metric.mustache"),
  DOTNET_EC2_WINDOWS_DEFAULT_CLIENT_CALL_TRACE("/expected-data-template/dotnet/ec2/windows/client-call-trace.mustache"),

  /** DotNet EC2 Asg Test Case Validations */
  DOTNET_EC2_ASG_OUTGOING_HTTP_CALL_LOG("/expected-data-template/dotnet/ec2/asg/outgoing-http-call-log.mustache"),
  DOTNET_EC2_ASG_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/dotnet/ec2/asg/outgoing-http-call-metric.mustache"),
  DOTNET_EC2_ASG_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/dotnet/ec2/asg/outgoing-http-call-trace.mustache"),

  DOTNET_EC2_ASG_AWS_SDK_CALL_LOG("/expected-data-template/dotnet/ec2/asg/aws-sdk-call-log.mustache"),
  DOTNET_EC2_ASG_AWS_SDK_CALL_METRIC("/expected-data-template/dotnet/ec2/asg/aws-sdk-call-metric.mustache"),
  DOTNET_EC2_ASG_AWS_SDK_CALL_TRACE("/expected-data-template/dotnet/ec2/asg/aws-sdk-call-trace.mustache"),

  DOTNET_EC2_ASG_REMOTE_SERVICE_LOG("/expected-data-template/dotnet/ec2/asg/remote-service-log.mustache"),
  DOTNET_EC2_ASG_REMOTE_SERVICE_METRIC("/expected-data-template/dotnet/ec2/asg/remote-service-metric.mustache"),
  DOTNET_EC2_ASG_REMOTE_SERVICE_TRACE("/expected-data-template/dotnet/ec2/asg/remote-service-trace.mustache"),

  DOTNET_EC2_ASG_CLIENT_CALL_LOG("/expected-data-template/dotnet/ec2/asg/client-call-log.mustache"),
  DOTNET_EC2_ASG_CLIENT_CALL_METRIC("/expected-data-template/dotnet/ec2/asg/client-call-metric.mustache"),
  DOTNET_EC2_ASG_CLIENT_CALL_TRACE("/expected-data-template/dotnet/ec2/asg/client-call-trace.mustache"),

  /** DotNet EC2 ADOT SigV4 (Stand Alone ADOT) Test Case Validations */
  DOTNET_EC2_ADOT_SIGV4_OUTGOING_HTTP_CALL_LOG(
      "/expected-data-template/dotnet/ec2/adot-sigv4/outgoing-http-call-log.mustache"),
  DOTNET_EC2_ADOT_SIGV4_OUTGOING_HTTP_CALL_METRIC(
      "/expected-data-template/dotnet/ec2/adot-sigv4/outgoing-http-call-metric.mustache"),
  DOTNET_EC2_ADOT_SIGV4_OUTGOING_HTTP_CALL_TRACE(
      "/expected-data-template/dotnet/ec2/adot-sigv4/outgoing-http-call-trace.mustache"),

  DOTNET_EC2_ADOT_SIGV4_AWS_SDK_CALL_LOG("/expected-data-template/dotnet/ec2/adot-sigv4/aws-sdk-call-log.mustache"),
  DOTNET_EC2_ADOT_SIGV4_AWS_SDK_CALL_METRIC("/expected-data-template/dotnet/ec2/adot-sigv4/aws-sdk-call-metric.mustache"),
  DOTNET_EC2_ADOT_SIGV4_AWS_SDK_CALL_TRACE("/expected-data-template/dotnet/ec2/adot-sigv4/aws-sdk-call-trace.mustache"),

  DOTNET_EC2_ADOT_SIGV4_REMOTE_SERVICE_LOG("/expected-data-template/dotnet/ec2/adot-sigv4/remote-service-log.mustache"),
  DOTNET_EC2_ADOT_SIGV4_REMOTE_SERVICE_METRIC("/expected-data-template/dotnet/ec2/adot-sigv4/remote-service-metric.mustache"),
  DOTNET_EC2_ADOT_SIGV4_REMOTE_SERVICE_TRACE("/expected-data-template/dotnet/ec2/adot-sigv4/remote-service-trace.mustache"),

  DOTNET_EC2_ADOT_SIGV4_CLIENT_CALL_LOG("/expected-data-template/dotnet/ec2/adot-sigv4/client-call-log.mustache"),
  DOTNET_EC2_ADOT_SIGV4_CLIENT_CALL_METRIC("/expected-data-template/dotnet/ec2/adot-sigv4/client-call-metric.mustache"),
  DOTNET_EC2_ADOT_SIGV4_CLIENT_CALL_TRACE("/expected-data-template/dotnet/ec2/adot-sigv4/client-call-trace.mustache"),

  /** DotNet K8s Test Case Validations */
  DOTNET_K8S_OUTGOING_HTTP_CALL_LOG("/expected-data-template/dotnet/k8s/outgoing-http-call-log.mustache"),
  DOTNET_K8S_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/dotnet/k8s/outgoing-http-call-metric.mustache"),
  DOTNET_K8S_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/dotnet/k8s/outgoing-http-call-trace.mustache"),

  DOTNET_K8S_AWS_SDK_CALL_LOG("/expected-data-template/dotnet/k8s/aws-sdk-call-log.mustache"),
  DOTNET_K8S_AWS_SDK_CALL_METRIC("/expected-data-template/dotnet/k8s/aws-sdk-call-metric.mustache"),
  DOTNET_K8S_AWS_SDK_CALL_TRACE("/expected-data-template/dotnet/k8s/aws-sdk-call-trace.mustache"),

  DOTNET_K8S_REMOTE_SERVICE_LOG("/expected-data-template/dotnet/k8s/remote-service-log.mustache"),
  DOTNET_K8S_REMOTE_SERVICE_METRIC("/expected-data-template/dotnet/k8s/remote-service-metric.mustache"),
  DOTNET_K8S_REMOTE_SERVICE_TRACE("/expected-data-template/dotnet/k8s/remote-service-trace.mustache"),

  DOTNET_K8S_CLIENT_CALL_LOG("/expected-data-template/dotnet/k8s/client-call-log.mustache"),
  DOTNET_K8S_CLIENT_CALL_METRIC("/expected-data-template/dotnet/k8s/client-call-metric.mustache"),
  DOTNET_K8S_CLIENT_CALL_TRACE("/expected-data-template/dotnet/k8s/client-call-trace.mustache"),


  /** DotNet EKS Linux Test Case Validations */
  DOTNET_EKS_LINUX_OUTGOING_HTTP_CALL_LOG("/expected-data-template/dotnet/eks/linux/outgoing-http-call-log.mustache"),
  DOTNET_EKS_LINUX_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/dotnet/eks/linux/outgoing-http-call-metric.mustache"),
  DOTNET_EKS_LINUX_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/dotnet/eks/linux/outgoing-http-call-trace.mustache"),

  DOTNET_EKS_LINUX_AWS_SDK_CALL_LOG("/expected-data-template/dotnet/eks/linux/aws-sdk-call-log.mustache"),
  DOTNET_EKS_LINUX_AWS_SDK_CALL_METRIC("/expected-data-template/dotnet/eks/linux/aws-sdk-call-metric.mustache"),
  DOTNET_EKS_LINUX_AWS_SDK_CALL_TRACE("/expected-data-template/dotnet/eks/linux/aws-sdk-call-trace.mustache"),

  DOTNET_EKS_LINUX_REMOTE_SERVICE_LOG("/expected-data-template/dotnet/eks/linux/remote-service-log.mustache"),
  DOTNET_EKS_LINUX_REMOTE_SERVICE_METRIC("/expected-data-template/dotnet/eks/linux/remote-service-metric.mustache"),
  DOTNET_EKS_LINUX_REMOTE_SERVICE_TRACE("/expected-data-template/dotnet/eks/linux/remote-service-trace.mustache"),

  DOTNET_EKS_LINUX_CLIENT_CALL_LOG("/expected-data-template/dotnet/eks/linux/client-call-log.mustache"),
  DOTNET_EKS_LINUX_CLIENT_CALL_METRIC("/expected-data-template/dotnet/eks/linux/client-call-metric.mustache"),
  DOTNET_EKS_LINUX_CLIENT_CALL_TRACE("/expected-data-template/dotnet/eks/linux/client-call-trace.mustache"),

  /** NODE EKS Test Case Validations */
  NODE_EKS_OUTGOING_HTTP_CALL_LOG("/expected-data-template/node/eks/outgoing-http-call-log.mustache"),
  NODE_EKS_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/node/eks/outgoing-http-call-metric.mustache"),
  NODE_EKS_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/node/eks/outgoing-http-call-trace.mustache"),

  NODE_EKS_AWS_SDK_CALL_LOG("/expected-data-template/node/eks/aws-sdk-call-log.mustache"),
  NODE_EKS_AWS_SDK_CALL_METRIC("/expected-data-template/node/eks/aws-sdk-call-metric.mustache"),
  NODE_EKS_AWS_SDK_CALL_TRACE("/expected-data-template/node/eks/aws-sdk-call-trace.mustache"),

  NODE_EKS_REMOTE_SERVICE_LOG("/expected-data-template/node/eks/remote-service-log.mustache"),
  NODE_EKS_REMOTE_SERVICE_METRIC("/expected-data-template/node/eks/remote-service-metric.mustache"),
  NODE_EKS_REMOTE_SERVICE_TRACE("/expected-data-template/node/eks/remote-service-trace.mustache"),

  NODE_EKS_CLIENT_CALL_LOG("/expected-data-template/node/eks/client-call-log.mustache"),
  NODE_EKS_CLIENT_CALL_METRIC("/expected-data-template/node/eks/client-call-metric.mustache"),
  NODE_EKS_CLIENT_CALL_TRACE("/expected-data-template/node/eks/client-call-trace.mustache"),
  
  /** Node EC2 Default Test Case Validations */
  NODE_EC2_DEFAULT_OUTGOING_HTTP_CALL_LOG("/expected-data-template/node/ec2/default/outgoing-http-call-log.mustache"),
  NODE_EC2_DEFAULT_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/node/ec2/default/outgoing-http-call-metric.mustache"),
  NODE_EC2_DEFAULT_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/node/ec2/default/outgoing-http-call-trace.mustache"),

  NODE_EC2_DEFAULT_AWS_SDK_CALL_LOG("/expected-data-template/node/ec2/default/aws-sdk-call-log.mustache"),
  NODE_EC2_DEFAULT_AWS_SDK_CALL_METRIC("/expected-data-template/node/ec2/default/aws-sdk-call-metric.mustache"),
  NODE_EC2_DEFAULT_AWS_SDK_CALL_TRACE("/expected-data-template/node/ec2/default/aws-sdk-call-trace.mustache"),

  NODE_EC2_DEFAULT_REMOTE_SERVICE_LOG("/expected-data-template/node/ec2/default/remote-service-log.mustache"),
  NODE_EC2_DEFAULT_REMOTE_SERVICE_METRIC("/expected-data-template/node/ec2/default/remote-service-metric.mustache"),
  NODE_EC2_DEFAULT_REMOTE_SERVICE_TRACE("/expected-data-template/node/ec2/default/remote-service-trace.mustache"),

  NODE_EC2_DEFAULT_CLIENT_CALL_LOG("/expected-data-template/node/ec2/default/client-call-log.mustache"),
  NODE_EC2_DEFAULT_CLIENT_CALL_METRIC("/expected-data-template/node/ec2/default/client-call-metric.mustache"),
  NODE_EC2_DEFAULT_CLIENT_CALL_TRACE("/expected-data-template/node/ec2/default/client-call-trace.mustache"),

  /** Node EC2 ASG Test Case Validations */
  NODE_EC2_ASG_OUTGOING_HTTP_CALL_LOG("/expected-data-template/node/ec2/asg/outgoing-http-call-log.mustache"),
  NODE_EC2_ASG_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/node/ec2/asg/outgoing-http-call-metric.mustache"),
  NODE_EC2_ASG_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/node/ec2/asg/outgoing-http-call-trace.mustache"),

  NODE_EC2_ASG_AWS_SDK_CALL_LOG("/expected-data-template/node/ec2/asg/aws-sdk-call-log.mustache"),
  NODE_EC2_ASG_AWS_SDK_CALL_METRIC("/expected-data-template/node/ec2/asg/aws-sdk-call-metric.mustache"),
  NODE_EC2_ASG_AWS_SDK_CALL_TRACE("/expected-data-template/node/ec2/asg/aws-sdk-call-trace.mustache"),

  NODE_EC2_ASG_REMOTE_SERVICE_LOG("/expected-data-template/node/ec2/asg/remote-service-log.mustache"),
  NODE_EC2_ASG_REMOTE_SERVICE_METRIC("/expected-data-template/node/ec2/asg/remote-service-metric.mustache"),
  NODE_EC2_ASG_REMOTE_SERVICE_TRACE("/expected-data-template/node/ec2/asg/remote-service-trace.mustache"),

  NODE_EC2_ASG_CLIENT_CALL_LOG("/expected-data-template/node/ec2/asg/client-call-log.mustache"),
  NODE_EC2_ASG_CLIENT_CALL_METRIC("/expected-data-template/node/ec2/asg/client-call-metric.mustache"),
  NODE_EC2_ASG_CLIENT_CALL_TRACE("/expected-data-template/node/ec2/asg/client-call-trace.mustache"),

  /** Node EC2 ASG Test Case Validations */
  NODE_K8S_OUTGOING_HTTP_CALL_LOG("/expected-data-template/node/k8s/outgoing-http-call-log.mustache"),
  NODE_K8S_OUTGOING_HTTP_CALL_METRIC("/expected-data-template/node/k8s/outgoing-http-call-metric.mustache"),
  NODE_K8S_OUTGOING_HTTP_CALL_TRACE("/expected-data-template/node/k8s/outgoing-http-call-trace.mustache"),

  NODE_K8S_AWS_SDK_CALL_LOG("/expected-data-template/node/k8s/aws-sdk-call-log.mustache"),
  NODE_K8S_AWS_SDK_CALL_METRIC("/expected-data-template/node/k8s/aws-sdk-call-metric.mustache"),
  NODE_K8S_AWS_SDK_CALL_TRACE("/expected-data-template/node/k8s/aws-sdk-call-trace.mustache"),

  NODE_K8S_REMOTE_SERVICE_LOG("/expected-data-template/node/k8s/remote-service-log.mustache"),
  NODE_K8S_REMOTE_SERVICE_METRIC("/expected-data-template/node/k8s/remote-service-metric.mustache"),
  NODE_K8S_REMOTE_SERVICE_TRACE("/expected-data-template/node/k8s/remote-service-trace.mustache"),

  NODE_K8S_CLIENT_CALL_LOG("/expected-data-template/node/k8s/client-call-log.mustache"),
  NODE_K8S_CLIENT_CALL_METRIC("/expected-data-template/node/k8s/client-call-metric.mustache"),
  NODE_K8S_CLIENT_CALL_TRACE("/expected-data-template/node/k8s/client-call-trace.mustache"),

  /** Node EC2 ADOT SigV4 (Stand Alone ADOT) Test Case Validations */
  NODE_EC2_ADOT_SIGV4_OUTGOING_HTTP_CALL_LOG(
      "/expected-data-template/node/ec2/adot-sigv4/outgoing-http-call-log.mustache"),
  NODE_EC2_ADOT_SIGV4_OUTGOING_HTTP_CALL_METRIC(
      "/expected-data-template/node/ec2/adot-sigv4/outgoing-http-call-metric.mustache"),
  NODE_EC2_ADOT_SIGV4_OUTGOING_HTTP_CALL_TRACE(
      "/expected-data-template/node/ec2/adot-sigv4/outgoing-http-call-trace.mustache"),

  NODE_EC2_ADOT_SIGV4_AWS_SDK_CALL_LOG("/expected-data-template/node/ec2/adot-sigv4/aws-sdk-call-log.mustache"),
  NODE_EC2_ADOT_SIGV4_AWS_SDK_CALL_METRIC("/expected-data-template/node/ec2/adot-sigv4/aws-sdk-call-metric.mustache"),
  NODE_EC2_ADOT_SIGV4_AWS_SDK_CALL_TRACE("/expected-data-template/node/ec2/adot-sigv4/aws-sdk-call-trace.mustache"),

  NODE_EC2_ADOT_SIGV4_REMOTE_SERVICE_LOG("/expected-data-template/node/ec2/adot-sigv4/remote-service-log.mustache"),
  NODE_EC2_ADOT_SIGV4_REMOTE_SERVICE_METRIC("/expected-data-template/node/ec2/adot-sigv4/remote-service-metric.mustache"),
  NODE_EC2_ADOT_SIGV4_REMOTE_SERVICE_TRACE("/expected-data-template/node/ec2/adot-sigv4/remote-service-trace.mustache"),

  NODE_EC2_ADOT_SIGV4_CLIENT_CALL_LOG("/expected-data-template/node/ec2/adot-sigv4/client-call-log.mustache"),
  NODE_EC2_ADOT_SIGV4_CLIENT_CALL_METRIC("/expected-data-template/node/ec2/adot-sigv4/client-call-metric.mustache"),
  NODE_EC2_ADOT_SIGV4_CLIENT_CALL_TRACE("/expected-data-template/node/ec2/adot-sigv4/client-call-trace.mustache"),

  /** Node ECS Test Case Validations */
  NODE_ECS_HC_CALL_LOG("/expected-data-template/node/ecs/hc-log.mustache"),
  NODE_ECS_HC_CALL_METRIC("/expected-data-template/node/ecs/hc-metric.mustache"),
  NODE_ECS_HC_CALL_TRACE("/expected-data-template/node/ecs/hc-trace.mustache"),

  /** Node Lambda Test Case Validations */
  NODE_LAMBDA_INVOKE_LOG("/expected-data-template/node/lambda/lambda-invoke-log.mustache"),
  NODE_LAMBDA_INVOKE_METRIC("/expected-data-template/node/lambda/lambda-invoke-metric.mustache"),
  NODE_LAMBDA_INVOKE_TRACE("/expected-data-template/node/lambda/lambda-invoke-trace.mustache"),
  NODE_LAMBDA_AWS_SDK_CALL_LOG("/expected-data-template/node/lambda/aws-sdk-call-log.mustache"),
  NODE_LAMBDA_AWS_SDK_CALL_METRIC("/expected-data-template/node/lambda/aws-sdk-call-metric.mustache"),

  /** Python Lambda Test Case Validations */
  PYTHON_LAMBDA_INVOKE_LOG("/expected-data-template/python/lambda/lambda-invoke-log.mustache"),
  PYTHON_LAMBDA_INVOKE_METRIC("/expected-data-template/python/lambda/lambda-invoke-metric.mustache"),
  PYTHON_LAMBDA_INVOKE_TRACE("/expected-data-template/python/lambda/lambda-invoke-trace.mustache"),
  PYTHON_LAMBDA_AWS_SDK_CALL_LOG("/expected-data-template/python/lambda/aws-sdk-call-log.mustache"),
  PYTHON_LAMBDA_AWS_SDK_CALL_METRIC("/expected-data-template/python/lambda/aws-sdk-call-metric.mustache"),

  /** DotNet Lambda Test Case Validations */
  DOTNET_LAMBDA_INVOKE_LOG("/expected-data-template/dotnet/lambda/lambda-invoke-log.mustache"),
  DOTNET_LAMBDA_INVOKE_METRIC("/expected-data-template/dotnet/lambda/lambda-invoke-metric.mustache"),
  DOTNET_LAMBDA_INVOKE_TRACE("/expected-data-template/dotnet/lambda/lambda-invoke-trace.mustache"),
  DOTNET_LAMBDA_AWS_SDK_CALL_LOG("/expected-data-template/dotnet/lambda/aws-sdk-call-log.mustache"),
  DOTNET_LAMBDA_AWS_SDK_CALL_METRIC("/expected-data-template/dotnet/lambda/aws-sdk-call-metric.mustache"),

  /** Java Lambda Test Case Validations */
  JAVA_LAMBDA_INVOKE_LOG("/expected-data-template/java/lambda/lambda-invoke-log.mustache"),
  JAVA_LAMBDA_INVOKE_METRIC("/expected-data-template/java/lambda/lambda-invoke-metric.mustache"),
  JAVA_LAMBDA_INVOKE_TRACE("/expected-data-template/java/lambda/lambda-invoke-trace.mustache"),
  JAVA_LAMBDA_AWS_SDK_CALL_LOG("/expected-data-template/java/lambda/aws-sdk-call-log.mustache"),
  JAVA_LAMBDA_AWS_SDK_CALL_METRIC("/expected-data-template/java/lambda/aws-sdk-call-metric.mustache"),
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
