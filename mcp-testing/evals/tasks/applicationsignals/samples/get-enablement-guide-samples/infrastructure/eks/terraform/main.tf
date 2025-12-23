terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

# IAM role for EKS cluster
resource "aws_iam_role" "cluster_role" {
  name = "${var.app_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster_role.name
}

# IAM role for EKS node group
resource "aws_iam_role" "node_role" {
  name = "${var.app_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_role.name
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_role.name
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_role.name
}

resource "aws_iam_role_policy_attachment" "node_s3_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  role       = aws_iam_role.node_role.name
}

resource "aws_iam_role_policy_attachment" "node_ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.node_role.name
}

# Launch template for metadata options
resource "aws_launch_template" "node_template" {
  name_prefix = "${var.app_name}-node-"
  
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 3
  }
}

# EKS Cluster with default capacity for Windows (matches CDK defaultCapacity: isWindows ? 1 : 0)
resource "aws_eks_cluster" "app_cluster" {
  name     = "${var.app_name}-cluster"
  role_arn = aws_iam_role.cluster_role.arn
  version  = "1.30"

  vpc_config {
    subnet_ids              = [for subnet in data.aws_subnets.public.ids : subnet if !contains(["us-east-1e"], data.aws_availability_zones.available.names[index(data.aws_subnets.public.ids, subnet)])]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]
}

# Default Linux node group (matches CDK's defaultCapacity behavior)
resource "aws_eks_node_group" "default_linux_nodes" {
  count = var.platform == "windows" ? 1 : 0
  
  cluster_name    = aws_eks_cluster.app_cluster.name
  node_group_name = "default-linux-nodes"
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = data.aws_subnets.public.ids

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  instance_types = ["t3.medium"]
  ami_type       = "AL2_x86_64"

  launch_template {
    id      = aws_launch_template.node_template.id
    version = "$Latest"
  }

  depends_on = [
    aws_launch_template.node_template,
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
    aws_iam_role_policy_attachment.node_s3_policy,
    aws_iam_role_policy_attachment.node_ssm_policy
  ]
}

data "aws_availability_zones" "available" {
  state = "available"
}

# EKS Node Group
resource "aws_eks_node_group" "app_nodes" {
  cluster_name    = aws_eks_cluster.app_cluster.name
  node_group_name = "default-node-group"
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = data.aws_subnets.public.ids

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  instance_types = [var.platform == "windows" ? "t3.large" : "t3.medium"]
  ami_type       = var.platform == "windows" ? "WINDOWS_CORE_2022_x86_64" : "AL2_x86_64"

  launch_template {
    id      = aws_launch_template.node_template.id
    version = "$Latest"
  }

  dynamic "taint" {
    for_each = var.platform == "windows" ? [1] : []
    content {
      key    = "os"
      value  = "windows"
      effect = "NO_SCHEDULE"
    }
  }

  depends_on = [
    aws_launch_template.node_template,
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
    aws_iam_role_policy_attachment.node_s3_policy,
    aws_iam_role_policy_attachment.node_ssm_policy
  ]
}

# Configure Kubernetes provider
provider "kubernetes" {
  host                   = aws_eks_cluster.app_cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.app_cluster.certificate_authority[0].data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.app_cluster.name]
  }
}



# Update aws-auth ConfigMap to add Windows node role mapping
resource "kubernetes_config_map_v1_data" "aws_auth" {
  count = var.platform == "windows" ? 1 : 0
  
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = jsonencode([
      {
        rolearn  = aws_iam_role.node_role.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes", "eks:kube-proxy-windows"]
      }
    ])
  }

  force = true

  depends_on = [
    aws_eks_cluster.app_cluster,
    aws_eks_node_group.app_nodes,
    aws_eks_node_group.default_linux_nodes
  ]
}

# Attach the required policy for the VPC Resource Controller (needed for Windows IPAM)
resource "aws_iam_role_policy_attachment" "cluster_vpc_resource_controller_policy" {
  count      = var.platform == "windows" ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster_role.name
}

# Configure VPC CNI Add-on for Windows IPAM using native addon
resource "aws_eks_addon" "vpc_cni_windows_config" {
  count = var.platform == "windows" ? 1 : 0
  
  cluster_name = aws_eks_cluster.app_cluster.name
  addon_name   = "vpc-cni"
  
  configuration_values = jsonencode({
    enableWindowsIpam = "true"
  })
  
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  
  depends_on = [
    aws_eks_cluster.app_cluster,
    aws_iam_role_policy_attachment.cluster_vpc_resource_controller_policy
  ]
}

# Kubernetes Deployment
resource "kubernetes_deployment" "app" {
  metadata {
    name = var.app_name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = var.app_name
      }
    }

    template {
      metadata {
        labels = {
          app = var.app_name
        }
      }

      spec {
        node_selector = {
          "kubernetes.io/os" = var.platform
        }

        dynamic "toleration" {
          for_each = var.platform == "windows" ? [1] : []
          content {
            key    = "os"
            value  = "windows"
            effect = "NoSchedule"
          }
        }

        container {
          image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${var.image_name}:latest"
          name  = var.app_name

          port {
            container_port = var.port
          }

          env {
            name  = "PORT"
            value = tostring(var.port)
          }

          env {
            name  = "AWS_REGION"
            value = data.aws_region.current.name
          }

          lifecycle {
            post_start {
              exec {
                command = var.platform == "windows" ? [
                  "powershell", "-Command", 
                  "Start-Process powershell -ArgumentList '-File C:\\app\\generate-traffic.ps1' -WindowStyle Hidden"
                ] : ["sh", "-c", "nohup bash /app/generate-traffic.sh > /dev/null 2>&1 &"]
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    aws_eks_node_group.app_nodes,
    aws_eks_node_group.default_linux_nodes
  ]
}

# Kubernetes Service
resource "kubernetes_service" "app" {
  metadata {
    name = "${var.app_name}-service"
  }

  spec {
    selector = {
      app = var.app_name
    }

    port {
      port        = var.port
      target_port = var.port
    }

    type = "LoadBalancer"
  }

  depends_on = [kubernetes_deployment.app]
}