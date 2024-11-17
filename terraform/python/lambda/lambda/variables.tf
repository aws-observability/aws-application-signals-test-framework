variable "function_name" {
  type        = string
  description = "Name of sample app function / API gateway"
  default     = "aws-opentelemetry-distro-nodejs"
}

variable "sdk_layer_name" {
  type        = string
  description = "Name of published SDK layer"
  default     = "AWSOpenTelemetryDistroPython"
}

variable "tracing_mode" {
  type        = string
  description = "Lambda function tracing mode"
  default     = "Active"
}

variable "runtime" {
  type        = string
  description = "Python runtime version used for sample Lambda Function"
  default     = "python3.13"
}

variable "architecture" {
  type        = string
  description = "Lambda function architecture, valid values are arm64 or x86_64"
  default     = "x86_64"
}

variable "is_canary" {
  type        = bool
  default     = false
  description = "Whether to create the resource or not"
}

variable "region" {
  type        = string
  description = "Lambda function running region, default value is us-west-2"
  default     = "us-west-2"
}

variable "layer_artifacts_directory" {
  type        = string
  default = "./layer_artifacts"
  description = "Lambda layer and function artifacts directory"
}
