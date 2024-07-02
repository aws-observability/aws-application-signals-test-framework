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

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "aws_ssh_key" {
  key_name   = "instance_key-${var.test_id}"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

locals {
  ssh_key_name        = aws_key_pair.aws_ssh_key.key_name
  private_key_content = tls_private_key.ssh_key.private_key_pem
}

data "aws_ami" "ami" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["al20*-ami-minimal-*-x86_64"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "image-type"
    values = ["machine"]
  }

  filter {
    name   = "root-device-name"
    values = ["/dev/xvda"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_launch_configuration" "launch_configuration" {
  image_id                    = data.aws_ami.ami.id
  instance_type               = "t3.micro"
  key_name                    = "DotnetE2EManual"
  associate_public_ip_address = true
  iam_instance_profile        = "APP_SIGNALS_EC2_TEST_ROLE"
  security_groups             = [aws_default_vpc.default.default_security_group_id]

  user_data = <<-EOF
    #!/bin/bash
    set -o errexit
    cd /home/ec2-user

    # Install DotNet and wget
    sudo yum install -y wget
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    sudo wget -O /etc/yum.repos.d/microsoft-prod.repo https://packages.microsoft.com/config/fedora/37/prod.repo
    sudo dnf install -y dotnet-sdk-8.0
    sudo yum install unzip -y

    # Copy in CW Agent configuration
    agent_config='${replace(replace(file("./amazon-cloudwatch-agent.json"), "/\\s+/", ""), "$REGION", var.aws_region)}'
    echo $agent_config > amazon-cloudwatch-agent.json

    # Get and run CW agent rpm
    ${var.get_cw_agent_rpm_command}
    sudo rpm -U ./cw-agent.rpm
    sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:./amazon-cloudwatch-agent.json

    # Get ADOT distro and unzip it
    ${var.get_adot_distro_command}

    # Get and run the sample application with configuration
    aws s3 cp ${var.sample_app_zip} ./dotnet-sample-app.zip
    unzip -o dotnet-sample-app.zip

    # Get Absolute Path
    current_dir=$(pwd)

    # Export environment variables for instrumentation
    cd ./asp_frontend_service
    export INSTALL_DIR=../dotnet-distro
    export CORECLR_ENABLE_PROFILING=1
    export CORECLR_PROFILER={918728DD-259F-4A6A-AC2B-B85E1B658318}
    export CORECLR_PROFILER_PATH=$current_dir/dotnet-distro/linux-x64/OpenTelemetry.AutoInstrumentation.Native.so
    export DOTNET_ADDITIONAL_DEPS=$current_dir/dotnet-distro/AdditionalDeps
    export DOTNET_SHARED_STORE=$current_dir/dotnet-distro/store
    export DOTNET_STARTUP_HOOKS=$current_dir/dotnet-distro/net/OpenTelemetry.AutoInstrumentation.StartupHook.dll
    export OTEL_DOTNET_AUTO_HOME=$current_dir/dotnet-distro
    export OTEL_DOTNET_AUTO_PLUGINS="AWS.Distro.OpenTelemetry.AutoInstrumentation.Plugin, AWS.Distro.OpenTelemetry.AutoInstrumentation"
    export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
    export OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4316
    export OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT=http://127.0.0.1:4316/v1/metrics
    export OTEL_METRICS_EXPORTER=none
    export OTEL_RESOURCE_ATTRIBUTES=service.name=dotnet-sample-application-${var.test_id}
    export OTEL_AWS_APPLICATION_SIGNALS_ENABLED=true
    export OTEL_TRACES_SAMPLER=always_on
    export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://127.0.0.1:4316/v1/traces
    sudo -E nohup dotnet run &

    # The application needs time to come up and reach a steady state, this should not take longer than 30 seconds
    sleep 30
    EOF
}

resource "aws_autoscaling_group" "asg" {
  name                 = "dotnet-ec2-single-asg-${var.test_id}"
  min_size             = 1
  max_size             = 1
  launch_configuration = aws_launch_configuration.launch_configuration.name
  vpc_zone_identifier  = [data.aws_subnets.default_subnets.ids.0]
}

resource "aws_instance" "remote_service_instance" {
  ami                                  = data.aws_ami.ami.id # Amazon Linux 2 (free tier)
  instance_type                        = "t3.micro"
  key_name                             = local.ssh_key_name
  iam_instance_profile                 = "APP_SIGNALS_EC2_TEST_ROLE"
  vpc_security_group_ids               = [aws_default_vpc.default.default_security_group_id]
  associate_public_ip_address          = true
  instance_initiated_shutdown_behavior = "terminate"
  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "remote-service-${var.test_id}"
  }
}

resource "null_resource" "remote_service_setup" {
  connection {
    type        = "ssh"
    user        = var.user
    private_key = local.private_key_content
    host        = aws_instance.remote_service_instance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOF
      #!/bin/bash

      # Install DotNet and wget
      sudo yum install wget -y
      sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
      sudo wget -O /etc/yum.repos.d/microsoft-prod.repo https://packages.microsoft.com/config/fedora/37/prod.repo
      sudo dnf install -y dotnet-sdk-8.0
      sudo yum install unzip -y

      # Copy in CW Agent configuration
      agent_config='${replace(replace(file("./amazon-cloudwatch-agent.json"), "/\\s+/", ""), "$REGION", var.aws_region)}'
      echo $agent_config > amazon-cloudwatch-agent.json

      # Get and run CW agent rpm
      ${var.get_cw_agent_rpm_command}
      sudo rpm -U ./cw-agent.rpm
      sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:./amazon-cloudwatch-agent.json

      # Get ADOT distro and unzip it
      ${var.get_adot_distro_command}

      # Get and run the sample application with configuration
      aws s3 cp ${var.sample_app_zip} ./dotnet-sample-app.zip
      unzip -o dotnet-sample-app.zip


      # Get Absolute Path
      current_dir=$(pwd)
      echo $current_dir

      # Export environment variables for instrumentation
      cd ./asp_remote_service
      export CORECLR_ENABLE_PROFILING=1
      export CORECLR_PROFILER={918728DD-259F-4A6A-AC2B-B85E1B658318}
      export CORECLR_PROFILER_PATH=$current_dir/dotnet-distro/linux-x64/OpenTelemetry.AutoInstrumentation.Native.so
      export DOTNET_ADDITIONAL_DEPS=$current_dir/dotnet-distro/AdditionalDeps
      export DOTNET_SHARED_STORE=$current_dir/dotnet-distro/store
      export DOTNET_STARTUP_HOOKS=$current_dir/dotnet-distro/net/OpenTelemetry.AutoInstrumentation.StartupHook.dll
      export OTEL_DOTNET_AUTO_HOME=$current_dir/dotnet-distro
      export OTEL_DOTNET_AUTO_PLUGINS="AWS.Distro.OpenTelemetry.AutoInstrumentation.Plugin, AWS.Distro.OpenTelemetry.AutoInstrumentation"
      export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
      export OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4316
      export OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT=http://127.0.0.1:4316/v1/metrics
      export OTEL_METRICS_EXPORTER=none
      export OTEL_RESOURCE_ATTRIBUTES=service.name=dotnet-sample-application-${var.test_id}
      export OTEL_AWS_APPLICATION_SIGNALS_ENABLED=true
      export OTEL_TRACES_SAMPLER=always_on
      nohup dotnet run &

      # The application needs time to come up and reach a steady state, this should not take longer than 30 seconds
      sleep 30

      EOF
    ]
  }

  depends_on = [aws_instance.remote_service_instance]
}
