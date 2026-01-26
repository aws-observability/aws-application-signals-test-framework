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

output "instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.app_instance.id
}

output "instance_public_ip" {
  description = "EC2 Instance Public IP"
  value       = aws_instance.app_instance.public_ip
}

output "health_check_url" {
  description = "Application Health Endpoint"
  value       = "http://${aws_instance.app_instance.public_ip}:${var.port}${var.health_check_path}"
}

output "buckets_api_url" {
  description = "Application Buckets API Endpoint"
  value       = "http://${aws_instance.app_instance.public_ip}:${var.port}/api/buckets"
}

output "s3_location" {
  description = "S3 location of application package"
  value       = "s3://${var.s3_bucket_name}/${var.s3_object_key}"
}

output "language" {
  description = "Application language"
  value       = var.language
}

output "platform" {
  description = "Application platform"
  value       = "windows"
}