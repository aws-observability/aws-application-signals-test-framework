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

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# Define the provider for AWS
provider "aws" {}

resource "aws_default_vpc" "default" {}

data "aws_subnets" "default_subnets" {
  filter {
    name   = "vpc-id"
    values = [aws_default_vpc.default.id]
  }
}

data "aws_iam_role" "e2e_test_task_role" {
  # change
  name = "ecsE2ETestRole"
}

data "aws_iam_role" "e2e_test_task_execution_role" {
  # change
  name = "ecsE2ETestExecutionRole"
}

data "template_file" "main_service" {
  template = file("./resources/main-service.json.tpl")

  vars = {
    app_image        = var.sample_app_image
    app_service_name = "${var.sample_app_name}"
    aws_region       = var.aws_region
    init_image       = var.adot_instrumentation_image
    cwagent_image    = var.cwagent_image
  }
}

resource "aws_ecs_cluster" "e2e_test" {
  name = var.ecs_cluster_name
}
resource "aws_ecs_task_definition" "main_service" {
  family                   = var.sample_app_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = data.aws_iam_role.e2e_test_task_execution_role.arn
  task_role_arn            = data.aws_iam_role.e2e_test_task_role.arn
  cpu                      = 512
  memory                   = 1024
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = data.template_file.main_service.rendered
  volume {
    name = "opentelemetry-auto-instrumentation"
  }
}

resource "aws_ecs_service" "main_service" {
  name                    = var.sample_app_name
  cluster                 = aws_ecs_cluster.e2e_test.id
  task_definition         = aws_ecs_task_definition.main_service.arn
  desired_count           = 1
  enable_ecs_managed_tags = true
  launch_type             = "FARGATE"

  network_configuration {
    security_groups  = [aws_default_vpc.default.default_security_group_id]
    subnets          = data.aws_subnets.default_subnets.ids
    assign_public_ip = true
  }

  wait_for_steady_state = true
}