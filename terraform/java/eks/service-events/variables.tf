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

# NodePort for the sample app Service. NodePort is cluster-wide, so when this test runs in PARALLEL
# with the version jobs (java-eks-parallel-test.yml uses 30100..30108) the calling workflow passes a
# value above that range to avoid "port already allocated". Defaults to 30100 for the standalone /
# sequential workflow, which has the cluster to itself.
variable "main_node_port" {
  default = 30100
}

variable "java_app_image" {
  default = "<ECR_IMAGE_LINK>:<TAG>"
}

variable "account_id" {
  default = "<AWS_ACCOUNT_ID>"
}

variable "service_events_packages_include" {
  default = "com.amazon.sampleapp"
}

variable "service_events_git_commit_sha" {
  default = "0000000000000000000000000000000000000000"
}

variable "service_events_git_repo_url" {
  default = "https://github.com/aws-observability/aws-otel-java-instrumentation"
}

variable "service_events_latency_thresholds" {
  default = "GET /aws-sdk-call:1"
}
