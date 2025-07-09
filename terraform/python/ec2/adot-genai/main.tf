terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
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
  ami                                   = data.aws_ami.ami.id
  instance_type                         = var.cpu_architecture == "x86_64" ? "t3.medium" : "t4g.medium"
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
  
  user_data = base64encode(<<-EOF
#!/bin/bash
yum update -y
yum install -y python3.12 python3.12-pip unzip

mkdir -p /app
cd /app
aws s3 cp ${var.service_zip_url} langchain-service.zip
unzip langchain-service.zip

# Having issues installing dependencies from ec2-requirements.txt as these dependencies are quite large and cause timeouts/memory issues on EC2, manually installing instead
python3.12 -m pip install fastapi uvicorn[standard] --no-cache-dir
python3.12 -m pip install boto3 botocore setuptools --no-cache-dir
python3.12 -m pip install opentelemetry-api opentelemetry-sdk opentelemetry-semantic-conventions --no-cache-dir
python3.12 -m pip install langchain langchain-community langchain_aws --no-cache-dir
python3.12 -m pip install python-dotenv openlit --no-cache-dir
python3.12 -m pip install openinference-instrumentation-langchain aws_opentelemetry_distro_genai_beta --no-cache-dir

export AWS_REGION=${var.aws_region}
export OTEL_PROPAGATORS=tracecontext,xray,baggage
export OTEL_PYTHON_DISTRO=aws_distro
export OTEL_PYTHON_CONFIGURATOR=aws_configurator
export OTEL_EXPORTER_OTLP_LOGS_HEADERS="x-aws-log-group=test/genesis,x-aws-log-stream=default,x-aws-metric-namespace=genesis"
export OTEL_RESOURCE_ATTRIBUTES="service.name=langchain-traceloop-app"
export AGENT_OBSERVABILITY_ENABLED="true"

nohup opentelemetry-instrument python3.12 server.py > /var/log/langchain-service.log 2>&1 &
EOF
  )

  tags = {
    Name = "langchain-service-${var.test_id}"
  }
}

output "langchain_service_instance_id" {
  value = aws_instance.main_service_instance.id
}

output "langchain_service_public_ip" {
  value = aws_instance.main_service_instance.public_ip
}