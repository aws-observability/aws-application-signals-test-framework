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
    values = ["al2023-ami-*-${var.cpu_architecture}"]
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
yum install -y python3.12 python3.12-pip unzip bc

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

# Create traffic generator script
cat > /app/generate_traffic.sh << 'TRAFFIC_EOF'
#!/bin/bash

# Configuration
SERVER_URL="$${SERVER_URL:-http://localhost:8000}"
ENDPOINT="$$SERVER_URL/ai-chat"
DELAY_SECONDS="$${DELAY_SECONDS:-3600}"
NUM_REQUESTS="$${NUM_REQUESTS:-0}"
TIMEOUT="$${TIMEOUT:-30}"


# Array of sample messages
MESSAGES=(
    "What is the weather like today?"
    "Tell me a joke"
    "How do I make a cup of coffee?"
    "What are the benefits of exercise?"
    "Explain quantum computing in simple terms"
    "What's the capital of France?"
    "How do I learn programming?"
    "What are some healthy breakfast ideas?"
    "Tell me about artificial intelligence"
    "How can I improve my productivity?"
    "What's the difference between a list and a tuple in Python?"
    "Explain the concept of microservices"
    "What are some best practices for API design?"
    "How does machine learning work?"
    "What's the purpose of unit testing?"
)

# Function to send a request
send_request() {
    local message="$$1"
    local request_num="$$2"
    local timestamp=$$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$$timestamp] Request #$$request_num"
    echo "Message: \"$$message\""
    
    local trace_id_header="$${TRACE_ID:-${var.trace_id}}"
    
    echo "Using Trace ID: $$trace_id_header"
    
    response=$$(curl -s -X POST "$$ENDPOINT" \
        -H "Content-Type: application/json" \
        -H "X-Amzn-Trace-Id: $$trace_id_header" \
        -d "{\"message\": \"$$message\"}" \
        -m "$$TIMEOUT" \
        -w "\nHTTP_STATUS:%%{http_code}\nTIME_TOTAL:%%{time_total}")
    
    http_status=$$(echo "$$response" | grep "HTTP_STATUS:" | cut -d: -f2)
    time_total=$$(echo "$$response" | grep "TIME_TOTAL:" | cut -d: -f2)
    body=$$(echo "$$response" | sed '/HTTP_STATUS:/d' | sed '/TIME_TOTAL:/d')
    
    if [ "$$http_status" = "200" ]; then
        echo "Success ($${time_total}s)"
        echo "Response: $$body"
    else
        echo "Error: HTTP $$http_status"
        if [ -n "$$body" ]; then
            echo "Response: $$body"
        fi
    fi
    echo "---"
}

echo "Starting traffic generation to $$ENDPOINT"
echo "Configuration:"
echo "  - Delay between requests: $${DELAY_SECONDS}s"
echo "  - Request timeout: $${TIMEOUT}s"
echo "  - Number of requests: $${NUM_REQUESTS} (0 = infinite)"
echo "  - Requests per minute: ~$$((60 / DELAY_SECONDS))"
echo "=================================="

count=0
start_time=$$(date +%s)

while true; do
    random_index=$$((RANDOM % $${#MESSAGES[@]}))
    message="$${MESSAGES[$$random_index]}"
    
    count=$$((count + 1))
    
    send_request "$$message" "$$count"
    
    if [ "$$NUM_REQUESTS" -gt 0 ] && [ "$$count" -ge "$$NUM_REQUESTS" ]; then
        end_time=$$(date +%s)
        duration=$$((end_time - start_time))
        echo "Completed $$count requests in $${duration}s"
        break
    fi
    
    if [ $$((count % 10)) -eq 0 ]; then
        current_time=$$(date +%s)
        elapsed=$$((current_time - start_time))
        rate=$$(echo "scale=2; $$count / $$elapsed * 60" | bc 2>/dev/null || echo "N/A")
        echo "Progress: $$count requests sent, Rate: $${rate} req/min"
    fi
    
    sleep "$$DELAY_SECONDS"
done
TRAFFIC_EOF

chmod +x /app/generate_traffic.sh

# Start traffic generator in background
echo "Starting traffic generator..."
nohup /app/generate_traffic.sh > /var/log/traffic-generator.log 2>&1 &
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