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





variable "user" {
  default = "ec2-user"
}

variable "trace_id" {
  description = "Trace ID for X-Ray tracing"
  default = "Root=1-5759e988-bd862e3fe1be46a994272793;Parent=53995c3f42cd8ad8;Sampled=1"
}

variable "get_adot_wheel_command" {
  description = "Command to get and install ADOT wheel"
  default = "python3.12 -m pip install aws-opentelemetry-distro"
}