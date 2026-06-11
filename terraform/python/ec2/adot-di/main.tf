# ------------------------------------------------------------------------
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# -------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

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
  ami                                  = data.aws_ami.ami.id
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

      sudo yum install wget -y
      sudo yum install unzip -y

      # Python 3.12 is required for Dynamic Instrumentation (sys.monitoring).
      # Dnf does not have the module for python 3.8, 3.10, 3.12, 3.13, therefore we need to manually install it.
      if [ "${var.language_version}" == "3.8" ] || [ "${var.language_version}" = "3.10" ] || [ "${var.language_version}" = "3.12" ] || [ "${var.language_version}" = "3.13" ]; then
          sudo dnf groupinstall "Development Tools" -y
          sudo dnf install openssl-devel sqlite-devel libffi-devel -y

          cd /usr/src
          sudo wget https://www.python.org/ftp/python/${var.language_version}.0/Python-${var.language_version}.0.tgz
          sudo tar xzf Python-${var.language_version}.0.tgz

          cd Python-${var.language_version}.0
          sudo ./configure
          sudo make install

          cd ~
      else
        sudo dnf install -y python${var.language_version}
        sudo dnf install -y python${var.language_version}-pip
      fi

      sudo yum install ec2-instance-connect -y

      agent_config='${replace(replace(file("./amazon-cloudwatch-agent.json"), "/\\s+/", ""), "$REGION", var.aws_region)}'
      echo $agent_config > amazon-cloudwatch-agent.json

      ${var.get_cw_agent_rpm_command}
      sudo rpm -U ./cw-agent.rpm
      sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:./amazon-cloudwatch-agent.json

      sudo python${var.language_version} -m pip install importlib-metadata==8.4.0 "protobuf>=3.19,<5.0"
      sudo python${var.language_version} -m pip install grpcio --only-binary=:all:

      ${var.get_adot_wheel_command}

      aws s3 cp ${var.sample_app_zip} ./python-sample-app.zip
      unzip -o python-sample-app.zip

      cd ./django_frontend_service
      sudo python${var.language_version} -m pip install -r ec2-requirements.txt

      # Dynamic Instrumentation only: no App Signals span/metric/log pipeline.
      export DJANGO_SETTINGS_MODULE="django_frontend_service.settings"
      export OTEL_PYTHON_DISTRO=aws_distro
      export OTEL_PYTHON_CONFIGURATOR=aws_configurator
      export OTEL_AWS_DYNAMIC_INSTRUMENTATION_ENABLED=true
      export OTEL_AWS_DYNAMIC_INSTRUMENTATION_BREAKPOINT_POLL_INTERVAL=15
      export OTEL_SERVICE_NAME=${var.service_name_prefix}-${var.test_id}
      export OTEL_RESOURCE_ATTRIBUTES="deployment.environment.name=${var.di_environment}"
      export AWS_REGION='${var.aws_region}'
      python${var.language_version} manage.py migrate
      nohup opentelemetry-instrument python${var.language_version} manage.py runserver 0.0.0.0:8000 --noreload &

      sleep 30

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
        sudo yum install nodejs aws-cli unzip tmux -y

        aws s3 cp s3://aws-appsignals-sample-app-prod-${var.aws_region}/traffic-generator.zip ./traffic-generator.zip
        unzip ./traffic-generator.zip -d ./

        npm install

        tmux new -s traffic-generator -d
        tmux send-keys -t traffic-generator "export MAIN_ENDPOINT=\"localhost:8000\"" C-m
        tmux send-keys -t traffic-generator "export ID=\"${var.test_id}\"" C-m
        tmux send-keys -t traffic-generator "npm start" C-m

      EOF
    ]
  }

  depends_on = [null_resource.main_service_setup]
}
