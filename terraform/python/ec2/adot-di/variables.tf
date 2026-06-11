# ------------------------------------------------------------------------
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# -------------------------------------------------------------------------

variable "test_id" {
  default = "dummy-123"
}

variable "aws_region" {
  default = "<aws-region>"
}

variable "user" {
  default = "ec2-user"
}

variable "sample_app_zip" {
  default = "s3://<bucket-name>/<zip>"
}

variable "traffic_generator_zip" {
  default = "s3://<bucket-name>/<zip>"
}

variable "get_adot_wheel_command" {
  default = "aws s3 cp s3://<bucket-name>/<whl> ./<whl> && pip install <whl>"
}

variable "get_cw_agent_rpm_command" {
  default = "<command> s3://<bucket-name>/<jar>"
}

variable "canary_type" {
  default = "python-ec2-adot-di"
}

# Dynamic Instrumentation requires Python 3.12+ (sys.monitoring).
variable "language_version" {
  default = "3.12"
}

variable "cpu_architecture" {
  default = "x86_64"
}

# IAM instance profile attached to the EC2 instance. Default matches the canonical name
# used across this repo's other python-ec2 canaries; override when running against an
# account that uses a different profile name.
variable "iam_instance_profile" {
  default = "APP_SIGNALS_EC2_TEST_ROLE"
}

# Application Signals control-plane endpoint the SDK polls for breakpoint configurations.
# Defaults to gamma; override to the prod endpoint once DI ships.
variable "di_api_url" {
  default = "https://application-signals-gamma.us-east-1.api.aws"
}

# Service identity for OTEL_SERVICE_NAME and the DI Environment field. Sourced from the
# workflow so the same values are used for terraform (which sets the env vars in
# user-data) and the awscurl payloads (which target the same identity).
variable "service_name_prefix" {
  default = "python-sample-application"
}

variable "di_environment" {
  default = "ec2:python-di-main-service-asg"
}
