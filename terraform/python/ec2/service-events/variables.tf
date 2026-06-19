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

variable "sample_app_zip" {
  default = "s3://<bucket-name>/<zip>"
}

variable "get_adot_wheel_command" {
  default = "aws s3 cp s3://<bucket-name>/<whl> ./<whl> && pip install <whl>"
}

variable "get_cw_agent_rpm_command" {
  default = "<command> s3://<bucket-name>/<jar>"
}

variable "language_version" {
  default = "3.10"
}

variable "cpu_architecture" {
  default = "x86_64"
}

# Function-instrumentation allowlist for Service Events FunctionCall telemetry.
# Empty by default the SDK instruments nothing; scope to the sample app's package so
# the `service.function.duration` metric is emitted for the Django views.
variable "service_events_packages_include" {
  default = "frontend_service_app"
}

# VCS provenance for Service Events. When OTEL_AWS_SERVICE_EVENTS_GIT_COMMIT_SHA /
# OTEL_AWS_SERVICE_EVENTS_GIT_REPO_URL are set, the SDK stamps every emitted event with
# vcs.ref.head.revision / vcs.repository.url.full. Defaulted to deterministic test values so
# the validator can assert these provenance fields (format-matched, not pinned to a real SHA).
variable "service_events_git_commit_sha" {
  default = "0000000000000000000000000000000000000000"
}

variable "service_events_git_repo_url" {
  default = "https://github.com/aws-observability/aws-application-signals-test-framework"
}

# Per-endpoint latency thresholds for latency-triggered IncidentSnapshots.
# Format: "METHOD route:threshold_ms" (Django routes omit the leading slash). The traffic
# generator hits /aws-sdk-call (a real SDK call, always > a few ms, returns HTTP 200), so a
# 1ms threshold deterministically fires a trigger_type="latency" incident (no exception, 200).
variable "service_events_latency_thresholds" {
  default = "GET aws-sdk-call:1"
}
