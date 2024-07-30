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

variable "kube_directory_path" {
    default = "./.kube"
}

variable "aws_region" {
  default = "<e.g. us-east-1>"
}

variable "eks_cluster_name" {
  default = "<cluster-name>"
}

variable "eks_cluster_context_name" {
  default = "<region>.<cluster-name>"
}

variable "test_namespace" {
  default = "python-app-namespace"
}

variable "service_account_aws_access" {
  default = "python-app-service-account"
}

variable "python_app_image" {
  default = "<ECR_IMAGE_LINK>:<TAG>"
}

variable "python_remote_app_image" {
  default = "<ECR_IMAGE_LINK>:<TAG>"
}

variable "rds_mysql_cluster_endpoint" {
  default = "example.cluster-example.eu-west-1.rds.amazonaws.com"
}

variable "rds_mysql_cluster_database" {
  default = "example_database"
}

variable "rds_mysql_cluster_username" {
  default = "username"
}

variable "rds_mysql_cluster_password" {
  default = "password"
}

variable "account_id" {
  default = "<AWS_ACCOUNT_ID>"
}
