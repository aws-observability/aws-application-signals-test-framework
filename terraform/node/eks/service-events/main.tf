# ------------------------------------------------------------------------
# Copyright 2023 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License").
# You may not use this file except in compliance with the License.
# A copy of the License is located at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# or in the "license" file accompanying this file. This file is distributed
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied. See the License for the specific language governing
# permissions and limitations under the License.
# -------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.16.1"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster" "testing_cluster" {
  name = var.eks_cluster_name
}
data "aws_eks_cluster_auth" "testing_cluster" {
  name = var.eks_cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.testing_cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.testing_cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.testing_cluster.token
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.testing_cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.testing_cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.testing_cluster.token
  load_config_file       = false
}

data "template_file" "kubeconfig_file" {
  template = file("./kubeconfig.tpl")
  vars = {
    CLUSTER_NAME : var.eks_cluster_context_name
    CA_DATA : data.aws_eks_cluster.testing_cluster.certificate_authority[0].data
    SERVER_ENDPOINT : data.aws_eks_cluster.testing_cluster.endpoint
    TOKEN = data.aws_eks_cluster_auth.testing_cluster.token
  }
}

resource "local_file" "kubeconfig" {
  content  = data.template_file.kubeconfig_file.rendered
  filename = "${var.kube_directory_path}/config"
}

locals {
  service_name = "node-sample-application-${var.test_id}"
}

resource "kubernetes_deployment_v1" "node_app_deployment" {
  metadata {
    name      = "node-app-deployment-${var.test_id}"
    namespace = var.test_namespace
    labels = {
      app = "node-app"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "node-app"
      }
    }
    template {
      metadata {
        labels = {
          app = "node-app"
        }
        annotations = {
          "instrumentation.opentelemetry.io/inject-nodejs" = "true"
        }
      }
      spec {
        service_account_name = var.service_account_aws_access
        container {
          name              = "back-end"
          image             = var.node_app_image
          image_pull_policy = "Always"
          command           = ["sh", "-c"]
          args              = ["node -e \"require('./index.js')\""]
          env {
            name  = "OTEL_SERVICE_NAME"
            value = local.service_name
          }
          env {
            name  = "OTEL_RESOURCE_ATTRIBUTES"
            value = "service.name=${local.service_name},deployment.environment.name=eks:service-events"
          }
          env {
            name  = "OTEL_AWS_SERVICE_EVENTS_PACKAGES_INCLUDE"
            value = var.service_events_packages_include
          }
          env {
            name  = "OTEL_AWS_SERVICE_EVENTS_DEPLOYMENT_ID"
            value = local.service_name
          }
          env {
            name  = "OTEL_AWS_SERVICE_EVENTS_GIT_COMMIT_SHA"
            value = var.service_events_git_commit_sha
          }
          env {
            name  = "OTEL_AWS_SERVICE_EVENTS_GIT_REPO_URL"
            value = var.service_events_git_repo_url
          }
          env {
            name  = "OTEL_AWS_SERVICE_EVENTS_LATENCY_THRESHOLDS"
            value = var.service_events_latency_thresholds
          }
          port {
            container_port = 8000
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "node_app_service" {
  depends_on = [kubernetes_deployment_v1.node_app_deployment]

  metadata {
    name      = "node-app-service"
    namespace = var.test_namespace
  }
  spec {
    type = "NodePort"
    selector = {
      app = "node-app"
    }
    port {
      protocol    = "TCP"
      port        = 8080
      target_port = 8000
      node_port   = 30100
    }
  }
}

resource "kubernetes_deployment_v1" "traffic_generator" {
  metadata {
    name      = "traffic-generator"
    namespace = var.test_namespace
    labels = {
      app = "traffic-generator"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "traffic-generator"
      }
    }
    template {
      metadata {
        labels = {
          app = "traffic-generator"
        }
      }
      spec {
        container {
          name              = "traffic-generator"
          image             = "${var.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/e2e-test-resource:traffic-generator"
          image_pull_policy = "Always"
          env {
            name  = "ID"
            value = var.test_id
          }
        }
      }
    }
  }
}
