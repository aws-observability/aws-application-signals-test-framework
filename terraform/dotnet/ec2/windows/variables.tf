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
  default = "windows-e2e-test-0"
}

variable "aws_region" {
  default = "<aws-region>"
}

variable "user" {
  default = "ec2-user"
}

variable "sample_app_zip" {
  default = "wget -O ./dotnet-sample-app.zip https://github.com/aws-observability/aws-application-signals-test-framework/raw/dotnetE2ETests/sample-apps/dotnet/dotnet-sample-app.zip"
}

variable "get_adot_distro_command" {
  default = "wget -O ./aws-distro-opentelemetry-dotnet-instrumentation-windows.zip https://github.com/aws-observability/aws-otel-dotnet-instrumentation/releases/download/v1.1.0/aws-distro-opentelemetry-dotnet-instrumentation-windows.zip; Expand-Archive -Path ./aws-distro-opentelemetry-dotnet-instrumentation-windows.zip -DestinationPath ./dotnet-distro -Force"
}

variable "get_cw_agent_msi_command" {
  default = "wget -O ./amazon-cloudwatch-agent.msi https://amazoncloudwatch-agent.s3.amazonaws.com/windows/amd64/latest/amazon-cloudwatch-agent.msi"
}