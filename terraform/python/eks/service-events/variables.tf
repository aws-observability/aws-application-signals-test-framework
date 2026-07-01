variable "test_id" {
  default = "dummy-123"
}

variable "aws_region" {
  default = "<aws-region>"
}

variable "eks_cluster_name" {
  default = "e2e-test-cluster"
}

variable "eks_cluster_context_name" {
  default = "e2e-test-cluster"
}

variable "kube_directory_path" {
  default = ""
}

variable "test_namespace" {
  default = "default"
}

variable "service_account_aws_access" {
  default = ""
}

variable "python_app_image" {
  default = "<ECR_IMAGE_LINK>:<TAG>"
}

variable "account_id" {
  default = "<AWS_ACCOUNT_ID>"
}

variable "service_events_packages_include" {
  default = "frontend_service_app"
}

variable "service_events_git_commit_sha" {
  default = "0000000000000000000000000000000000000000"
}

variable "service_events_git_repo_url" {
  default = "https://github.com/aws-observability/aws-application-signals-test-framework"
}

variable "service_events_latency_thresholds" {
  default = "GET aws-sdk-call:1"
}
