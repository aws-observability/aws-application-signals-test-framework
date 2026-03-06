variable "aws_region" {
  default = "us-west-2"
}

variable "test_id" {
  default = "dummy-123"
}

variable "service_zip_url" {
  description = "S3 URL for the service zip file"
}

variable "user" {
  default = "ec2-user"
}

variable "collector_s3_url" {
  description = "S3 URL for the agentcore collector binary"
}

variable "get_adot_wheel_command" {
  description = "Command to get and install ADOT wheel"
  default     = "python3.12 -m pip install aws-opentelemetry-distro"
}

variable "trace_id" {
  description = "Trace ID for X-Ray tracing"
  default     = "Root=1-5759e988-bd862e3fe1be46a994272793;Parent=53995c3f42cd8ad9;Sampled=1"
}
