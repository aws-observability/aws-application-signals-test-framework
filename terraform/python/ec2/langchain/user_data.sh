#!/bin/bash
yum update -y
yum install -y docker python3.12 python3.12-pip unzip

systemctl start docker
systemctl enable docker

# Download and setup LangChain service
mkdir -p /app
cd /app
aws s3 cp ${service_zip_url} langchain-service.zip
unzip langchain-service.zip

# Install dependencies
pip3.12 install -r ec2-requirements.txt

# Run with OTEL instrumentation
export OTEL_PYTHON_DISTRO=aws_distro
export OTEL_PYTHON_CONFIGURATOR=aws_configurator
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_LOGS_HEADERS="x-aws-log-group=test/genesis,x-aws-log-stream=default,x-aws-metric-namespace=genesis"
export OTEL_RESOURCE_ATTRIBUTES="service.name=langchain-traceloop-app"
export AGENT_OBSERVABILITY_ENABLED="true"

opentelemetry-instrument python3.12 server.py