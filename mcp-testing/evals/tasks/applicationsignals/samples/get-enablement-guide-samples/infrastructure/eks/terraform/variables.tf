variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "python-flask-eks"
}

variable "image_name" {
  description = "ECR image name"
  type        = string
  default     = "python-flask"
}

variable "port" {
  description = "Application port"
  type        = number
  default     = 5000
}

variable "health_check_path" {
  description = "Health check path"
  type        = string
  default     = "/health"
}

variable "language" {
  description = "Application language"
  type        = string
  default     = "python"
}