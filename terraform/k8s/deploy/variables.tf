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

variable "ssh_key" {
  default = "<MASTER_NODE_SSH_KEY>"
  description = "This variable is responsible for providing the SSH key of the master node to allow terraform to interact with the cluster"
}

variable "host" {
  default = "<HOST_IP_OR_DNS>"
  description = "This variable is responsible for defining which host (ec2 instance) we connect to for the K8s-on-EC2 test"
}

variable "adot_image" {
    default = "<cw_agent_image_address:latest>"
}

variable "cwagent_image" {
    default = "<adot_image_address:latest>"
}