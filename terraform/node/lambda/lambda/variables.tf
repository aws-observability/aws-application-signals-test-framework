variable "function_name" {
  type        = string
  description = "Name of sample app function / API gateway"
  default     = "aws-opentelemetry-distro-nodejs"
}

variable "sdk_layer_name" {
  type        = string
  description = "Name of published SDK layer"
  default     = "aws-opentelemetry-distro-nodejs"
}

variable "tracing_mode" {
  type        = string
  description = "Lambda function tracing mode"
  default     = "Active"
}

variable "runtime" {
  type        = string
  description = "NodeJS runtime version used for sample Lambda Function"
  default     = "nodejs16.x"
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

variable "layer_artifacts_directory" {
  type        = string
  default = "./layer_artifacts"
  description = "Lambda layer and function artifacts directory"
}
