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

variable "cpu_architecture" {
  default = "x86_64" # an alternative value is "arm64"
}

variable "language_version" {
  # none means to use the version packaged with the OS
  # other alternatives are "14", "16", "18", "20", "22"
  default = "none"
}

variable "sample_app_zip" {
  default = "s3://<bucket-name>/<zip>"
}

variable "get_adot_instrumentation_command" {
  default = "<get ADOT instrumentation command> && <install/prepare instrumentation command>"
}

variable "canary_type" {
  default = "node-ec2-default"
}