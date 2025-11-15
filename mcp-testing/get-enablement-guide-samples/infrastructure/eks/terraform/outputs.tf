output "cluster_name" {
  description = "EKS Cluster Name"
  value       = aws_eks_cluster.app_cluster.name
}

output "cluster_endpoint" {
  description = "EKS Cluster Endpoint"
  value       = aws_eks_cluster.app_cluster.endpoint
}

output "ecr_image_uri" {
  description = "ECR image URI used"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${var.image_name}:latest"
}

output "language" {
  description = "Application language"
  value       = var.language
}

output "health_check_url" {
  description = "Health check URL (available after LoadBalancer is ready)"
  value       = "http://<LoadBalancer-DNS>:${var.port}${var.health_check_path}"
}

output "buckets_api_url" {
  description = "Buckets API URL (available after LoadBalancer is ready)"
  value       = "http://<LoadBalancer-DNS>:${var.port}/api/buckets"
}