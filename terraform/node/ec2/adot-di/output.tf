# ------------------------------------------------------------------------
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# -------------------------------------------------------------------------

output "main_service_instance_id" {
  value = aws_instance.main_service_instance.id
}

output "main_service_public_ip" {
  value = aws_instance.main_service_instance.public_ip
}

output "ec2_instance_ami" {
  value = data.aws_ami.ami.id
}
