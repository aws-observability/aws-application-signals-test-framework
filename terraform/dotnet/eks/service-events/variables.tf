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

variable "dotnet_app_image" {
  default = "<ECR_IMAGE_LINK>:<TAG>"
}

variable "account_id" {
  default = "<AWS_ACCOUNT_ID>"
}

# Function-instrumentation allowlist for Service Events FunctionCall telemetry. In .NET v1
# FunctionCall covers framework-derived spans (HttpClient / AWS SDK / internal), matched against
# the derived function.name = "{Source.Name}.{OperationName}" — NOT user code namespaces, which is
# what the Java and Python equivalents take. Scope it to the HttpClient activity source so the
# sample app's /success and /failed-call routes produce `service.function.duration` data points.
variable "service_events_packages_include" {
  default = "System.Net.Http*"
}

variable "service_events_git_commit_sha" {
  default = "0000000000000000000000000000000000000000"
}

variable "service_events_git_repo_url" {
  default = "https://github.com/aws-observability/aws-application-signals-test-framework"
}

# Per-endpoint latency thresholds for latency-triggered IncidentSnapshots.
# Format: "METHOD route:threshold_ms". The route carries no leading slash: the operation key comes
# from ASP.NET Core's `http.route`, and MVC attribute routing normalizes the leading slash away, so
# `[Route("/success")]` resolves to `success`. /success makes an in-process HttpClient call to the
# app's own /health route, so a 1ms threshold deterministically fires a trigger_type="latency"
# incident at HTTP 200.
variable "service_events_latency_thresholds" {
  default = "GET success:1"
}
