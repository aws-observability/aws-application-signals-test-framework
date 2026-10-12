# ------------------------------------------------------------------------
# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
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

variable "get_adot_distro_command" {
  default = "aws s3 cp s3://<bucket-name>/<distro> ./<distro> && unzip <distro>"
}

variable "language_version" {
  default = "8.0"
}

variable "application_logs_log_group" {
  default = "otlp_logs"
}

variable "traces_use_legacy_path" {
  description = "Use the legacy SigV4 trace configuration instead of the upstream OTLP trace exporter."
  type        = bool
  default     = true
}

variable "otlp_compression" {
  description = "Compression applied to the OTLP exporters."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "gzip"], var.otlp_compression)
    error_message = "OTLP compression must be none or gzip."
  }
}
