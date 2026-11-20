# ------------------------------------------------------------------------
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License").
# You may not use this file except in compliance with the License.
# A copy of the License is located at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# or in the "license" file accompanying this file. This file is distributed
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied. See the License for the specific language governing
# permissions and limitations under the License.
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

variable "sample_app_jar" {
  default = "s3://<bucket-name>/<jar>"
}

variable "get_adot_jar_command" {
  default = "<command> s3://<bucket-name>/<jar>"
}

variable "get_cw_agent_rpm_command" {
  default = "<command> s3://<bucket-name>/<jar>"
}

variable "language_version" {
  default = "17"
}

variable "cpu_architecture" {
  default = "x86_64"
}

# Function-instrumentation allowlist for Service Events FunctionCall telemetry. The SDK
# instruments nothing by default; scope it to the sample app's package so the
# `service.function.duration` metric is emitted for the springboot controller methods.
variable "service_events_packages_include" {
  default = "com.amazon.sampleapp"
}

# VCS provenance for Service Events. When OTEL_AWS_SERVICE_EVENTS_GIT_COMMIT_SHA /
# OTEL_AWS_SERVICE_EVENTS_GIT_REPO_URL are set, the SDK stamps every emitted event with
# vcs.ref.head.revision / vcs.repository.url.full. The workflow passes the real github.sha;
# the default is a fallback for local `terraform apply` runs.
variable "service_events_git_commit_sha" {
  default = "0000000000000000000000000000000000000000"
}

variable "service_events_git_repo_url" {
  default = "https://github.com/aws-observability/aws-otel-java-instrumentation"
}

# Per-endpoint latency thresholds for latency-triggered IncidentSnapshots.
# Format: "METHOD route:threshold_ms" (Java/Spring routes keep the leading slash). The traffic
# generator hits /aws-sdk-call (a real SDK call, always > a few ms, returns HTTP 200), so a
# 1ms threshold deterministically fires a trigger_type="latency" incident (no exception, 200).
variable "service_events_latency_thresholds" {
  default = "GET /aws-sdk-call:1"
}
