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

# test_id is interpolated into resource names, the Service Events log group name and the
# SERVICE_NAME shell export on the instance, so restrict it to characters that are safe in all three.
variable "test_id" {
  default = "dummy-123"

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+$", var.test_id))
    error_message = "test_id must contain only alphanumeric characters and dashes."
  }
}

# Region under test. Unlike the other EC2 modules this has a real default because `terraform destroy`
# needs the provider region to resolve, and the destroy invocation passes only test_id and region.
variable "aws_region" {
  default = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier, for example us-east-1."
  }
}

variable "user" {
  default = "ec2-user"
}

variable "sample_app_zip" {
  default = "s3://<bucket-name>/<zip>"

  validation {
    condition     = can(regex("^(s3|https)://[^'\"\\s]+$", var.sample_app_zip))
    error_message = "sample_app_zip must be an s3:// or https:// URI containing no quotes or whitespace."
  }
}

# Artifact locations are URIs, not shell commands: the download logic lives in main.tf and only ever
# receives a validated URI, so nothing a caller supplies is executed on the instance.
variable "adot_distro_uri" {
  default = "s3://<bucket-name>/<distro>.zip"

  validation {
    condition     = can(regex("^(s3|https)://[^'\"\\s]+$", var.adot_distro_uri))
    error_message = "adot_distro_uri must be an s3:// or https:// URI containing no quotes or whitespace."
  }
}

variable "cw_agent_rpm_uri" {
  default = "https://amazoncloudwatch-agent.s3.amazonaws.com/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm"

  validation {
    condition     = can(regex("^(s3|https)://[^'\"\\s]+$", var.cw_agent_rpm_uri))
    error_message = "cw_agent_rpm_uri must be an s3:// or https:// URI containing no quotes or whitespace."
  }
}

# Interpolated into the build output path (bin/Debug/netcoreapp<version>/) and the dotnet-sdk
# package name, both of which are shell-expanded on the instance.
variable "language_version" {
  default = "8.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.language_version))
    error_message = "language_version must be a major.minor version, for example 8.0."
  }
}

# VCS provenance for Service Events. When OTEL_AWS_SERVICE_EVENTS_GIT_COMMIT_SHA /
# OTEL_AWS_SERVICE_EVENTS_GIT_REPO_URL are set, the SDK stamps every emitted event with
# vcs.ref.head.revision / vcs.repository.url.full.
#
# The placeholder default keeps `terraform destroy -var="test_id=..."` workable for cleaning up a
# leaked run, which is the only recovery path available given CI state is ephemeral. Requiring a
# real, non-zero SHA is enforced in the workflow's input validation instead, before any AWS
# credentials are requested.
variable "service_events_git_commit_sha" {
  default = "0000000000000000000000000000000000000000"

  validation {
    condition     = can(regex("^[a-f0-9]{40}$", var.service_events_git_commit_sha))
    error_message = "service_events_git_commit_sha must be a 40-character lowercase hex SHA."
  }
}

variable "service_events_git_repo_url" {
  default = "https://github.com/aws-observability/aws-application-signals-test-framework"

  validation {
    condition     = can(regex("^https://[^'\"\\s]+$", var.service_events_git_repo_url))
    error_message = "service_events_git_repo_url must be an https:// URL containing no quotes or whitespace."
  }
}

# Function-instrumentation allowlist for Service Events FunctionCall telemetry. In .NET v1
# FunctionCall covers framework-derived spans (HttpClient / AWS SDK / internal), matched against
# the derived function.name = "{Source.Name}.{OperationName}" — NOT user code namespaces. Scope
# it to the HttpClient activity source so the sample app's /success downstream call produces a
# `service.function.duration` (FunctionCall) data point.
variable "service_events_packages_include" {
  default = "System.Net.Http*"
}

# Per-endpoint latency thresholds for latency-triggered IncidentSnapshots.
# Format: "METHOD route:threshold_ms", comma-separated. The traffic generator hits /success, which
# makes an in-process HttpClient call to the app's own /health route (always > a few ms, returns
# HTTP 200), so a 1ms threshold deterministically fires a trigger_type="latency" incident (no
# exception, 200) without depending on DNS, TLS or egress to any public endpoint.
#
# The route carries no leading slash: the operation key comes from ASP.NET Core's `http.route`, and
# MVC attribute routing normalizes the leading slash away, so `[Route("/success")]` resolves to
# `success`. The expected-data templates still match either spelling, because a minimal-API sample
# app would keep the slash.
variable "service_events_latency_thresholds" {
  default = "GET success:1"
}
