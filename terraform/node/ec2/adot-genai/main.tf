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
  most_recent = true
  filter {
    name = "name"
    values = ["al2023-ami-*-x86_64"]
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
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "main_service_instance" {
  ami                                   = data.aws_ami.ami.id
  instance_type                         = "t3.medium"
  key_name                              = local.ssh_key_name
  iam_instance_profile                  = "APP_SIGNALS_EC2_TEST_ROLE"
  vpc_security_group_ids                = [aws_default_vpc.default.default_security_group_id]
  associate_public_ip_address           = true
  instance_initiated_shutdown_behavior  = "terminate"

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = 30
  }
  
  user_data = base64encode(<<-EOF
#!/bin/bash
yum update -y
yum install -y nodejs npm unzip bc

mkdir -p /app
cd /app
aws s3 cp ${var.service_zip_url} genai-service.zip
unzip genai-service.zip

# Navigate to genai-service directory and install dependencies
cd genai-service
npm install

export AWS_REGION=${var.aws_region}
export OTEL_EXPORTER_OTLP_LOGS_HEADERS="x-aws-log-group=test/genesis,x-aws-log-stream=default,x-aws-metric-namespace=genesis"
export OTEL_RESOURCE_ATTRIBUTES="service.name=langchain-traceloop-app"
export AGENT_OBSERVABILITY_ENABLED="true"

# Run the genai service from the genai-service directory
cd /app/genai-service
nohup node --require '@aws/aws-distro-opentelemetry-node-autoinstrumentation/register' --require ./customInstrumentation.js index.js > /var/log/langchain-service.log 2>&1 &

# Upload cloud-init logs to S3
aws s3 cp /var/log/cloud-init.log s3://adot-genai-js-test/cloud-init-logs/${var.test_id}/cloud-init.log
aws s3 cp /var/log/cloud-init-output.log s3://adot-genai-js-test/cloud-init-logs/${var.test_id}/cloud-init-output.log

# Wait for service to be ready
echo "Waiting for service to be ready..."
for i in {1..60}; do
  if curl -s http://localhost:8000/health > /dev/null 2>&1; then
    echo "Service is ready!"
    break
  fi
  echo "Attempt $i: Service not ready, waiting 5 seconds..."
  sleep 5
done

# Generate traffic directly
echo "Starting traffic generator..."
nohup bash -c '
for i in {1..5}; do
    message="What is the weather like today?"
    echo "[$(date)] Request $i: $message"
    curl -s -X POST http://localhost:8000/ai-chat \
        -H "Content-Type: application/json" \
        -H "X-Amzn-Trace-Id: ${var.trace_id}" \
        -d "{\"message\": \"$message\"}" \
        -m 30 \
    echo "Request $i completed"
    sleep 10
done
echo "Traffic generator completed"
' > /var/log/traffic-generator.log 2>&1 &

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