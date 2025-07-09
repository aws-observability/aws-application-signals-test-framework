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

variable "aws_region" {
  default = "us-west-2"
}

variable "test_id" {
  default = "dummy-123"
}

variable "service_zip_url" {
  description = "S3 URL for the service zip file"
}

variable "language_version" {
  default = "3.12"
}

variable "cpu_architecture" {
  default = "x86_64"
}

variable "user" {
  default = "ec2-user"
}