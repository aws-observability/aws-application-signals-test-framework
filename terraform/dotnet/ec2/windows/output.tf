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

output "sample_app_remote_service_private_ip" {
  value = aws_instance.remote_service_instance.private_ip
}

output "main_service_instance_id" {
  value = aws_instance.main_service_instance.id
}

output "remote_service_instance_id" {
  value = aws_instance.remote_service_instance.id
}

output "ec2_instance_ami" {
  value = data.aws_ami.ami.id
}

output "frontend_script_association_id" {
  value = aws_ssm_association.main_service_association.id
}

output "remote_script_association_id" {
  value = aws_ssm_association.remote_service_association.id
}