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
    name = "name"
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
  image_id      = data.aws_ami.ami.id
  instance_type = "t3.micro"
  key_name = local.ssh_key_name
  associate_public_ip_address = true
  iam_instance_profile = "APP_SIGNALS_EC2_TEST_ROLE"
  security_groups = [aws_default_vpc.default.default_security_group_id]

  user_data = <<-EOF
    #!/bin/bash

    # Install Python and wget
    sudo yum install wget -y
    sudo yum install unzip -y
    sudo dnf install -y python3.9
    sudo dnf install -y python3.9-pip

    # Copy in CW Agent configuration
    agent_config='${replace(replace(file("./amazon-cloudwatch-agent.json"), "/\\s+/", ""), "$REGION", var.aws_region)}'
    echo $agent_config > amazon-cloudwatch-agent.json

    # Get and run CW agent rpm
    ${var.get_cw_agent_rpm_command}
    sudo rpm -U ./cw-agent.rpm
    sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:./amazon-cloudwatch-agent.json

    # Get ADOT Wheel and install it
    ${var.get_adot_wheel_command}

    # Get and run the sample application with configuration
    aws s3 cp ${var.sample_app_zip} ./python-sample-app.zip
    unzip -o python-sample-app.zip

    # Export environment variables for instrumentation
    cd ./django_frontend_service
    # Delete the requests requirement as it is installed already using rpm. Only applicable for ec2 instances
    # created by Auto Scaling Groups
    sudo sed -i '/requests/d' ./ec2-requirements.txt
    python3.9 -m pip install -r ec2-requirements.txt
    export DJANGO_SETTINGS_MODULE="django_frontend_service.settings"
    export OTEL_PYTHON_DISTRO="aws_distro"
    export OTEL_PYTHON_CONFIGURATOR="aws_configurator"
    export OTEL_METRICS_EXPORTER=none
    export OTEL_TRACES_EXPORTER=otlp
    export OTEL_AWS_APPLICATION_SIGNALS_ENABLED=true
    export OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT=http://localhost:4315
    export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:4315
    export OTEL_EXPORTER_OTLP_TRACES_PROTOCOL=grpc
    export OTEL_EXPORTER_OTLP_METRICS_PROTOCOL=grpc
    export OTEL_SERVICE_NAME=python-sample-application-${var.test_id}
    export OTEL_TRACES_SAMPLER=always_on
    python3.9 manage.py migrate
    nohup opentelemetry-instrument python3.9 manage.py runserver 0.0.0.0:8000 --noreload &

    # The application needs time to come up and reach a steady state, this should not take longer than 30 seconds
    sleep 30

    # Deploy Traffic Generator
    sudo yum install nodejs aws-cli unzip tmux -y

    # Bring in the traffic generator files to EC2 Instance
    aws s3 cp s3://aws-appsignals-sample-app-prod-${var.aws_region}/traffic-generator.zip ./traffic-generator.zip
    unzip ./traffic-generator.zip -d ./

    # Install the traffic generator dependencies
    npm install

    tmux new -s traffic-generator -d
    tmux send-keys -t traffic-generator "export MAIN_ENDPOINT=\"localhost:8000\"" C-m
    tmux send-keys -t traffic-generator "export REMOTE_ENDPOINT=\"${aws_instance.remote_service_instance.private_ip}\"" C-m
    tmux send-keys -t traffic-generator "export ID=\"${var.test_id}\"" C-m
    tmux send-keys -t traffic-generator "npm start" C-m

    EOF
}

resource "aws_autoscaling_group" "asg" {
  name = "python-ec2-single-asg-${var.test_id}"
  min_size = 1
  max_size = 1
  launch_configuration = aws_launch_configuration.launch_configuration.name
  vpc_zone_identifier = [data.aws_subnets.default_subnets.ids.0]
  health_check_type = "EC2"
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
      #!/bin/bash

      # Install Python and wget
      sudo yum install wget -y
      sudo yum install unzip -y
      sudo dnf install -y python3.9
      sudo dnf install -y python3.9-pip

      # Copy in CW Agent configuration
      agent_config='${replace(replace(file("./amazon-cloudwatch-agent.json"), "/\\s+/", ""), "$REGION", var.aws_region)}'
      echo $agent_config > amazon-cloudwatch-agent.json

      # Get and run CW agent rpm
      ${var.get_cw_agent_rpm_command}
      sudo rpm -U ./cw-agent.rpm
      sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:./amazon-cloudwatch-agent.json

      # Get ADOT Wheel and install it
      ${var.get_adot_wheel_command}

      # Get and run the sample application with configuration
      aws s3 cp ${var.sample_app_zip} ./python-sample-app.zip
      unzip -o python-sample-app.zip

      # Export environment variables for instrumentation
      cd ./django_remote_service
      export DJANGO_SETTINGS_MODULE="django_remote_service.settings"
      python3.9 -m pip install -r requirements.txt --force-reinstall
      export OTEL_PYTHON_DISTRO="aws_distro"
      export OTEL_PYTHON_CONFIGURATOR="aws_configurator"
      export OTEL_METRICS_EXPORTER=none
      export OTEL_TRACES_EXPORTER=otlp
      export OTEL_AWS_APPLICATION_SIGNALS_ENABLED=true
      export OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT=http://localhost:4315
      export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:4315
      export OTEL_EXPORTER_OTLP_TRACES_PROTOCOL=grpc
      export OTEL_EXPORTER_OTLP_METRICS_PROTOCOL=grpc
      export OTEL_SERVICE_NAME=python-sample-remote-application-${var.test_id}
      export OTEL_TRACES_SAMPLER=always_on
      python3.9 manage.py migrate
      nohup opentelemetry-instrument python3.9 manage.py runserver 0.0.0.0:8001 --noreload &

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
