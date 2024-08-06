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

resource "aws_instance" "main_service_instance" {
  ami                                   = data.aws_ami.ami.id # Amazon Linux 2 (free tier)
  instance_type                         = "t3.micro"
  key_name                              = local.ssh_key_name
  iam_instance_profile                  = "APP_SIGNALS_EC2_TEST_ROLE"
  vpc_security_group_ids                = [aws_default_vpc.default.default_security_group_id]
  associate_public_ip_address           = true
  instance_initiated_shutdown_behavior  = "terminate"
  metadata_options {
    http_tokens = "required"
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
      # Install Java 11 and wget
      sudo yum install wget java-11-amazon-corretto -y

      # Copy in CW Agent configuration
      agent_config='${replace(replace(file("./amazon-cloudwatch-agent.json"), "/\\s+/", ""), "$REGION", var.aws_region)}'
      echo $agent_config > amazon-cloudwatch-agent.json

      # Get and run CW agent rpm
      ${var.get_cw_agent_rpm_command}
      sudo rpm -U ./cw-agent.rpm
      sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:./amazon-cloudwatch-agent.json

      # Get ADOT
      ${var.get_adot_jar_command}

      # Get and run the sample application with configuration
      aws s3 cp ${var.sample_app_jar} ./main-service.jar

      JAVA_TOOL_OPTIONS=' -javaagent:/home/ec2-user/adot.jar' \
      OTEL_METRICS_EXPORTER=none \
      OTEL_LOGS_EXPORT=none \
      OTEL_AWS_APPLICATION_SIGNALS_ENABLED=true \
      OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT=http://localhost:4316/v1/metrics \
      OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf \
      OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:4316/v1/traces \
      OTEL_RESOURCE_ATTRIBUTES=service.name=sample-application-${var.test_id} \
      nohup java -jar main-service.jar &> nohup.out &

      # The application needs time to come up and reach a steady state, this should not take longer than 30 seconds
      sleep 30

      EOF
    ]
  }

  depends_on = [aws_instance.main_service_instance]
}

resource "aws_instance" "remote_service_instance" {
  ami                                   = data.aws_ami.ami.id # Amazon Linux 2 (free tier)
  instance_type                         = "t3.micro"
  key_name                              = local.ssh_key_name
  iam_instance_profile                  = "APP_SIGNALS_EC2_TEST_ROLE"
  vpc_security_group_ids                = [aws_default_vpc.default.default_security_group_id]
  associate_public_ip_address           = true
  instance_initiated_shutdown_behavior  = "terminate"
  metadata_options {
    http_tokens = "required"
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
      # Install Java 11 and wget
      sudo yum install wget java-11-amazon-corretto -y

      # Copy in CW Agent configuration
      agent_config='${replace(replace(file("./amazon-cloudwatch-agent.json"), "/\\s+/", ""), "$REGION", var.aws_region)}'
      echo $agent_config > amazon-cloudwatch-agent.json

      # Get and run CW agent rpm
      ${var.get_cw_agent_rpm_command}
      sudo rpm -U ./cw-agent.rpm
      sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:./amazon-cloudwatch-agent.json

      # Get ADOT
      ${var.get_adot_jar_command}

      # Get and run the sample application with configuration
      aws s3 cp ${var.sample_remote_app_jar} ./remote-service.jar

      JAVA_TOOL_OPTIONS=' -javaagent:/home/ec2-user/adot.jar' \
      OTEL_METRICS_EXPORTER=none \
      OTEL_LOGS_EXPORT=none \
      OTEL_AWS_APPLICATION_SIGNALS_ENABLED=true \
      OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT=http://localhost:4316/v1/metrics \
      OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf \
      OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:4316/v1/traces \
      OTEL_RESOURCE_ATTRIBUTES=service.name=sample-remote-application-${var.test_id} \
      nohup java -jar remote-service.jar &> nohup.out &

      # The application needs time to come up and reach a steady state, this should not take longer than 30 seconds
      sleep 30

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
        aws s3 cp s3://aws-appsignals-sample-app-prod-${var.aws_region}/traffic-generator.zip ./traffic-generator.zip
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