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

# Must fetch an ADOT Java agent build that includes the profiler (to ./adot.jar).
variable "get_adot_jar_command" {
  default = "<command> s3://<bucket-name>/<jar>"
}

# Optional local path to an ADOT Java agent jar. When set, the jar is uploaded to the instance over
# SSH instead of running get_adot_jar_command, e.g. to test a locally built agent or when the
# instance cannot read the agent's S3 location.
variable "adot_jar_local_path" {
  default = ""
}

variable "language_version" {
  default = "17"
}

variable "cpu_architecture" {
  default = "x86_64"
}

# otelcol-contrib release that forwards profiles to CloudWatch. v0.148.0 is the minimum with a
# working profiles pipeline.
variable "otel_collector_version" {
  default = "0.148.0"
}

# Optional role the collector assumes to sign profile uploads, e.g. a role in an account enabled for
# CloudWatch Profiles when the test account is not. Empty = sign with the EC2 instance role.
variable "profiles_role_arn" {
  default = ""
}

# ADOT profiler sampling mode: "wall" (all threads, on- and off-CPU) or "cpu" (on-CPU only). The
# Java EC2 profiler validations assert wall-mode signals (thread.state), so keep "wall" for them.
variable "profiler_mode" {
  default = "wall"
}

# Sample aggregation for the main app: "none" | "full" | "sum", or empty (the default) to leave
# OTEL_AWS_PROFILER_AGGREGATION_MODE unset so the main app tests the agent's default (full). The
# other variants cover the remaining modes.
variable "profiler_aggregation_mode" {
  default = ""
}
