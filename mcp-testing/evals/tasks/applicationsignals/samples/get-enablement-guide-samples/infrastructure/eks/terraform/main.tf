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

resource "aws_iam_role_policy_attachment" "node_policy" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ])
  policy_arn = each.value
  role       = aws_iam_role.node_role.name
}

# EKS Cluster
resource "aws_eks_cluster" "app_cluster" {
  name     = "${var.app_name}-cluster"
  role_arn = aws_iam_role.cluster_role.arn
  version  = "1.30"

  vpc_config {
    subnet_ids              = data.aws_subnets.public.ids
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]
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

  instance_types = ["t3.medium"]

  # Launch template for IMDSv2 configuration
  launch_template {
    name    = aws_launch_template.node_group_lt.name
    version = aws_launch_template.node_group_lt.latest_version
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_policy
  ]
}

# Launch template for EKS node group with IMDSv2 hop limit
resource "aws_launch_template" "node_group_lt" {
  name_prefix   = "${var.app_name}-node-group-"
  image_id      = data.aws_ami.eks_worker.id
  instance_type = "t3.medium"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.app_name}-node"
    }
  }
}

# Get the latest EKS optimized AMI
data "aws_ami" "eks_worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-1.30-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
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

# Kubernetes ConfigMap for aws-auth
resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([
      {
        rolearn  = aws_iam_role.node_role.arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      },
      {
        rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/Admin"
        username = "admin"
        groups   = ["system:masters"]
      },
      {
        rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ReadOnly"
        username = "readonly"
        groups   = ["system:authenticated"]
      }
    ])
  }

  depends_on = [aws_eks_node_group.app_nodes]
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
                command = ["sh", "-c", "nohup bash /app/generate-traffic.sh > /dev/null 2>&1 &"]
              }
            }
          }
        }
      }
    }
  }

  depends_on = [aws_eks_node_group.app_nodes]
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

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment.app]
}