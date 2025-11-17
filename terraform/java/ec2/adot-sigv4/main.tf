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

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits = 4096
}

resource "aws_key_pair" "aws_ssh_key" {
  key_name = "instance_key-${var.test_id}"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

locals {
  ssh_key_name        = aws_key_pair.aws_ssh_key.key_name
  private_key_content = tls_private_key.ssh_key.private_key_pem
}

data "aws_ami" "ami" {
  owners = ["amazon"]
  most_recent      = true
  filter {
    name   = "name"
    values = ["al20*-ami-minimal-*-${var.cpu_architecture}"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
  filter {
    name   = "architecture"
    values = [var.cpu_architecture]
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

resource "aws_instance" "main_service_instance" {
  ami                                   = data.aws_ami.ami.id # Amazon Linux 2 (free tier)
  instance_type                         = var.cpu_architecture == "x86_64" ? "t3.micro" : "t4g.micro"
  key_name                              = local.ssh_key_name
  iam_instance_profile                  = "APP_SIGNALS_EC2_TEST_ROLE"
  vpc_security_group_ids                = [aws_default_vpc.default.default_security_group_id]
  associate_public_ip_address           = true
  instance_initiated_shutdown_behavior  = "terminate"

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = 5
  }

  tags = {
    Name = "main-service-${var.test_id}"
  }
}

resource "null_resource" "main_service_setup" {
  connection {
    type = "ssh"
    user = var.user
    private_key = local.private_key_content
    host = aws_instance.main_service_instance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOF
      # Make the Terraform fail if any step throws an error
      set -o errexit
      # Install wget
      sudo yum install wget -y
      # Install Java
      echo
      if [[ "${var.language_version}" == "8" ]]; then
        sudo yum install java-1.8.0-amazon-corretto -y
      else
        sudo yum install java-${var.language_version}-amazon-corretto -y
      fi

      sudo yum install ec2-instance-connect -y

      # Get ADOT
      ${var.get_adot_jar_command}

      # Get and run the sample application with configuration
      aws s3 cp ${var.sample_app_jar} ./main-service.jar --region us-east-1

      # OTEL_INSTRUMENTATION_COMMON_EXPERIMENTAL_CONTROLLER_TELEMETRY_ENABLED=true \
      export JAVA_TOOL_OPTIONS=' -javaagent:/home/ec2-user/adot.jar'
      export OTEL_LOGS_EXPORTER=otlp
      export OTEL_METRICS_EXPORTER=none
      export OTEL_TRACES_EXPORTER=otlp
      export OTEL_EXPORTER_OTLP_TRACES_PROTOCOL=http/protobuf
      export OTEL_EXPORTER_OTLP_LOGS_PROTOCOL=http/protobuf
      export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://xray.${var.aws_region}.amazonaws.com/v1/traces
      export OTEL_EXPORTER_OTLP_LOGS_ENDPOINT=https://logs.${var.aws_region}.amazonaws.com/v1/logs
      export OTEL_EXPORTER_OTLP_LOGS_HEADERS=x-aws-log-group=${var.application_logs_log_group},x-aws-log-stream=default
      export OTEL_RESOURCE_ATTRIBUTES=service.name=sample-application-${var.test_id}
      nohup java -jar main-service.jar &> nohup.out &

      # The application needs time to come up and reach a steady state, this should not take longer than 30 seconds
      sleep 30

      # Check if the application is up. If it is not up, then exit 1.
      attempt_counter=0
      max_attempts=30
      until $(curl --output /dev/null --silent --head --fail --max-time 5 $(echo "http://localhost:8080" | tr -d '"')); do
        if [ $attempt_counter -eq $max_attempts ];then
          echo "Failed to connect to endpoint."
          exit 1
        fi
        echo "Attempting to connect to the main endpoint. Tried $attempt_counter out of $max_attempts"
        attempt_counter=$(($attempt_counter+1))
        sleep 10
      done

      echo "Successfully connected to main endpoint"

      EOF
    ]
  }

  depends_on = [aws_instance.main_service_instance]
}

resource "aws_instance" "remote_service_instance" {
  ami                                   = data.aws_ami.ami.id # Amazon Linux 2 (free tier)
  instance_type                         = var.cpu_architecture == "x86_64" ? "t3.micro" : "t4g.micro"
  key_name                              = local.ssh_key_name
  iam_instance_profile                  = "APP_SIGNALS_EC2_TEST_ROLE"
  vpc_security_group_ids                = [aws_default_vpc.default.default_security_group_id]
  associate_public_ip_address           = true
  instance_initiated_shutdown_behavior  = "terminate"

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = 5
  }

  tags = {
    Name = "remote-service-${var.test_id}"
  }
}

resource "null_resource" "remote_service_setup" {
  connection {
    type = "ssh"
    user = var.user
    private_key = local.private_key_content
    host = aws_instance.remote_service_instance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOF
      # Make the Terraform fail if any step throws an error
      set -o errexit
      # Install wget
      sudo yum install wget -y
      # Install Java
      if [[ "${var.language_version}" == "8" ]]; then
        sudo yum install java-1.8.0-amazon-corretto -y
      else
        sudo yum install java-${var.language_version}-amazon-corretto -y
      fi

      # enable ec2 instance connect for debug
      sudo yum install ec2-instance-connect -y

      # Get ADOT
      ${var.get_adot_jar_command}

      # Get and run the sample application with configuration
      aws s3 cp ${var.sample_remote_app_jar} ./remote-service.jar --region us-east-1

      # OTEL_INSTRUMENTATION_COMMON_EXPERIMENTAL_CONTROLLER_TELEMETRY_ENABLED=true \
      export JAVA_TOOL_OPTIONS=' -javaagent:/home/ec2-user/adot.jar'
      export OTEL_LOGS_EXPORTER=otlp
      export OTEL_METRICS_EXPORTER=none
      export OTEL_TRACES_EXPORTER=otlp
      export OTEL_EXPORTER_OTLP_TRACES_PROTOCOL=http/protobuf
      export OTEL_EXPORTER_OTLP_LOGS_PROTOCOL=http/protobuf
      export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://xray.${var.aws_region}.amazonaws.com/v1/traces
      export OTEL_EXPORTER_OTLP_LOGS_ENDPOINT=https://logs.${var.aws_region}.amazonaws.com/v1/logs
      export OTEL_EXPORTER_OTLP_LOGS_HEADERS=x-aws-log-group=${var.application_logs_log_group},x-aws-log-stream=default
      OTEL_RESOURCE_ATTRIBUTES=service.name=sample-remote-application-${var.test_id} \
      nohup java -jar remote-service.jar &> nohup.out &

      # The application needs time to come up and reach a steady state, this should not take longer than 30 seconds
      sleep 30

      # Check if the application is up. If it is not up, then exit 1.
      attempt_counter=0
      max_attempts=30
      until $(curl --output /dev/null --silent --head --fail --max-time 5 $(echo "http://localhost:8080/healthcheck" | tr -d '"')); do
        if [ $attempt_counter -eq $max_attempts ];then
          echo "Failed to connect to endpoint."
          exit 1
        fi
        echo "Attempting to connect to the remote endpoint. Tried $attempt_counter out of $max_attempts"
        attempt_counter=$(($attempt_counter+1))
        sleep 10
      done

      echo "Successfully connected to remote endpoint"

      EOF
    ]
  }

  depends_on = [aws_instance.remote_service_instance]
}

resource "null_resource" "traffic_generator_setup" {
  connection {
    type = "ssh"
    user = var.user
    private_key = local.private_key_content
    host = aws_instance.main_service_instance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOF
        sudo yum install nodejs aws-cli unzip tmux -y

        # Bring in the traffic generator files to EC2 Instance
        aws s3 cp s3://aws-appsignals-sample-app-prod-us-east-1/traffic-generator.zip ./traffic-generator.zip --region us-east-1
        unzip ./traffic-generator.zip -d ./

        # Install the traffic generator dependencies
        npm install

        tmux new -s traffic-generator -d
        tmux send-keys -t traffic-generator "export MAIN_ENDPOINT=\"localhost:8080\"" C-m
        tmux send-keys -t traffic-generator "export REMOTE_ENDPOINT=\"${aws_instance.remote_service_instance.private_ip}\"" C-m
        tmux send-keys -t traffic-generator "export ID=\"${var.test_id}\"" C-m
        tmux send-keys -t traffic-generator "npm start" C-m

      EOF
    ]
  }

  depends_on = [null_resource.main_service_setup, null_resource.remote_service_setup]
}