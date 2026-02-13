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
  ami                                  = data.aws_ami.ami.id # Amazon Linux 2 (free tier)
  instance_type                        = var.cpu_architecture == "x86_64" ? "t3.micro" : "t4g.micro"
  key_name                             = local.ssh_key_name
  iam_instance_profile                 = "APP_SIGNALS_EC2_TEST_ROLE"
  vpc_security_group_ids               = [aws_default_vpc.default.default_security_group_id]
  associate_public_ip_address          = true
  instance_initiated_shutdown_behavior = "terminate"

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
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
    type        = "ssh"
    user        = var.user
    private_key = local.private_key_content
    host        = aws_instance.main_service_instance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOF
      #!/bin/bash

      # Make the Terraform fail if any step throws an error
      set -ex

      # Install Python and wget
      sudo yum install wget -y
      sudo yum install unzip -y

      # Install Python
      sudo dnf install -y python${var.language_version}
      sudo dnf install -y python${var.language_version}-pip

      # enable ec2 instance connect for debug
      sudo yum install ec2-instance-connect -y

      # Copy in CW Agent configuration
      agent_config='${replace(replace(file("./amazon-cloudwatch-agent.json"), "/\\s+/", ""), "$REGION", var.aws_region)}'
      echo $agent_config > amazon-cloudwatch-agent.json

      # Get and run CW agent rpm
      ${var.get_cw_agent_rpm_command}
      sudo rpm -U ./cw-agent.rpm
      sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:./amazon-cloudwatch-agent.json

      # Install modules with specific version so that it doesn't cause errors
      sudo python${var.language_version} -m pip install importlib-metadata==8.4.0 "protobuf>=3.19,<5.0"
      sudo python${var.language_version} -m pip install grpcio --only-binary=:all:

      # Get ADOT Wheel and install it
      ${var.get_adot_wheel_command}

      # Get and run the sample application with configuration
      aws s3 cp ${var.sample_app_zip} ./python-sample-app.zip
      unzip -o python-sample-app.zip

      # Export environment variables for instrumentation
      cd ./django_frontend_service
      sudo python${var.language_version} -m pip install -r ec2-requirements.txt
      export DJANGO_SETTINGS_MODULE="django_frontend_service.settings"
      export OTEL_PYTHON_DISTRO="aws_distro"
      export OTEL_PYTHON_CONFIGURATOR="aws_configurator"
      export OTEL_METRICS_EXPORTER=none
      export OTEL_LOGS_EXPORT=none
      export OTEL_TRACES_SAMPLER="xray"
      export OTEL_AWS_APPLICATION_SIGNALS_ENABLED=true
      export OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT=http://localhost:4316/v1/metrics
      export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
      export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:4316/v1/traces
      export OTEL_RESOURCE_ATTRIBUTES=service.name=main-${var.test_id}
      export AWS_XRAY_ADAPTIVE_SAMPLING_CONFIG="{version: 1.0, anomalyConditions: [{usage: sampling-boost}]}"
      python${var.language_version} manage.py migrate
      nohup opentelemetry-instrument python${var.language_version} manage.py runserver 0.0.0.0:8000 --noreload &> nohup.out &

      # The application needs time to come up and reach a steady state, this should not take longer than 30 seconds
      sleep 30

      # Check if the application is up. If it is not up, then exit 1.
      attempt_counter=0
      max_attempts=30
      until $(curl --output /dev/null --silent --head --fail --max-time 5 $(echo "http://localhost:8000" | tr -d '"')); do
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
  ami                                  = data.aws_ami.ami.id # Amazon Linux 2 (free tier)
  instance_type                        = var.cpu_architecture == "x86_64" ? "t3.micro" : "t4g.micro"
  key_name                             = local.ssh_key_name
  iam_instance_profile                 = "APP_SIGNALS_EC2_TEST_ROLE"
  vpc_security_group_ids               = [aws_default_vpc.default.default_security_group_id]
  associate_public_ip_address          = true
  instance_initiated_shutdown_behavior = "terminate"

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
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
    type        = "ssh"
    user        = var.user
    private_key = local.private_key_content
    host        = aws_instance.remote_service_instance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOF
      #!/bin/bash

      # Make the Terraform fail if any step throws an error
      set -ex

      # Install Python and wget
      sudo yum install wget -y
      sudo yum install unzip -y

      # Install Python
      sudo dnf install -y python${var.language_version}
      sudo dnf install -y python${var.language_version}-pip

      # enable ec2 instance connect for debug
      sudo yum install ec2-instance-connect -y

      # Copy in CW Agent configuration
      agent_config='${replace(replace(file("./amazon-cloudwatch-agent.json"), "/\\s+/", ""), "$REGION", var.aws_region)}'
      echo "$agent_config" > amazon-cloudwatch-agent.json

      # Get and run CW agent rpm
      ${var.get_cw_agent_rpm_command}
      sudo rpm -U ./cw-agent.rpm
      sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:./amazon-cloudwatch-agent.json

      # Install modules with specific version so that it doesn't cause errors
      sudo python${var.language_version} -m pip install importlib-metadata==8.4.0 "protobuf>=3.19,<5.0"
      sudo python${var.language_version} -m pip install grpcio --only-binary=:all:

      # Get ADOT Wheel and install it
      ${var.get_adot_wheel_command}

      # Get and run the sample application with configuration
      aws s3 cp ${var.sample_app_zip} ./python-sample-app.zip
      unzip -o python-sample-app.zip

      # Export environment variables for instrumentation
      cd ./django_remote_service
      sudo python${var.language_version} -m pip install -r requirements.txt --force-reinstall
      export DJANGO_SETTINGS_MODULE="django_remote_service.settings"
      export OTEL_PYTHON_DISTRO="aws_distro"
      export OTEL_PYTHON_CONFIGURATOR="aws_configurator"
      export OTEL_METRICS_EXPORTER=none
      export OTEL_LOGS_EXPORT=none
      export OTEL_TRACES_SAMPLER="xray"
      export OTEL_AWS_APPLICATION_SIGNALS_ENABLED=true
      export OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT=http://localhost:4316/v1/metrics
      export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
      export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:4316/v1/traces
      export OTEL_RESOURCE_ATTRIBUTES=service.name=remote-${var.test_id}
      export AWS_XRAY_ADAPTIVE_SAMPLING_CONFIG="{version: 1.0, anomalyConditions: [{errorCodeRegex: \"^500$\", usage: both}], anomalyCaptureLimit: {anomalyTracesPerSecond: 5}}"
      python${var.language_version} manage.py migrate
      nohup opentelemetry-instrument python${var.language_version} manage.py runserver 0.0.0.0:8001 --noreload &> nohup.out &

      # The application needs time to come up and reach a steady state, this should not take longer than 30 seconds
      sleep 30

      # Check if the application is up. If it is not up, then exit 1.
      attempt_counter=0
      max_attempts=30
      until $(curl --output /dev/null --silent --head --fail --max-time 5 $(echo "http://localhost:8001/healthcheck" | tr -d '"')); do
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
    type        = "ssh"
    user        = var.user
    private_key = local.private_key_content
    host        = aws_instance.main_service_instance.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOF
        set -ex

        # Load traffic generator script from local resources
        traffic_script='${file("./resources/traffic-generator.sh")}'
        echo "$traffic_script" > traffic-generator.sh

        chmod +x traffic-generator.sh

        MAIN_ENDPOINT="localhost:8000" REMOTE_ENDPOINT="${aws_instance.remote_service_instance.private_ip}" nohup ./traffic-generator.sh &> traffic_generator.log &

        sleep 10
      EOF
    ]
  }

  depends_on = [null_resource.main_service_setup, null_resource.remote_service_setup]
}
