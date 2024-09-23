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
  default = "<e.g. us-east-1>"
}

variable "ecs_cluster_name" {
  default = "e2e-test-java"
}

variable "sample_app_name" {
  default = ""
}

variable "sample_app_image" {
  default = ""
}

variable "sample_remote_app_image" {
  default = ""
}
variable "adot_instrumentation_image" {
  default = ""
}

variable "cwagent_image" {
  default = ""
}