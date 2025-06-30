variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "test_id" {
  description = "Test ID for resource naming"
  type        = string
}

variable "service_zip_url" {
  description = "S3 URL for the LangChain service zip file"
  type        = string
}