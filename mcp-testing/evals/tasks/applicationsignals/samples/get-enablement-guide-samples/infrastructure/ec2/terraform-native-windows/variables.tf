# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

variable "app_name" {
  description = "Name of the application"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket containing the application package"
  type        = string
}

variable "s3_object_key" {
  description = "S3 object key for the application package"
  type        = string
}

variable "language" {
  description = "Programming language of the application"
  type        = string
  default     = "dotnet"
}

variable "port" {
  description = "Port on which the application runs"
  type        = number
  default     = 5000
}

variable "health_check_path" {
  description = "Health check endpoint path"
  type        = string
  default     = "/health"
}

variable "windows_type" {
  description = "Type of Windows application (framework or aspnetcore)"
  type        = string
  default     = "aspnetcore"
  validation {
    condition     = contains(["framework", "aspnetcore"], var.windows_type)
    error_message = "windows_type must be either 'framework' or 'aspnetcore'."
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}