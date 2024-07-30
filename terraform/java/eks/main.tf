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

# get eks cluster
data "aws_eks_cluster" "testing_cluster" {
    name = var.eks_cluster_name
}
data "aws_eks_cluster_auth" "testing_cluster" {
    name = var.eks_cluster_name
}

# set up kubectl
provider "kubernetes" {
  host = data.aws_eks_cluster.testing_cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.testing_cluster.certificate_authority[0].data)
  token = data.aws_eks_cluster_auth.testing_cluster.token
}

provider "kubectl" {
  // Note: copy from eks module. Please avoid use shorted-lived tokens when running locally.
  // For more information: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs#exec-plugins
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
  content = data.template_file.kubeconfig_file.rendered
  filename = "${var.kube_directory_path}/config"
}

### Setting up the sample app on the cluster

resource "kubernetes_deployment" "sample_app_deployment" {

  metadata {
    name      = "sample-app-deployment-${var.test_id}"
    namespace = var.test_namespace
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "sample-app"
      }
    }
    template {
      metadata {
        labels = {
          app = "sample-app"
        }
        annotations = {
          # these annotations allow for OTel Java instrumentation
          "instrumentation.opentelemetry.io/inject-java" = "true"
        }
      }
      spec {
        service_account_name = var.service_account_aws_access
        container {
          name = "back-end"
          image = var.sample_app_image
          image_pull_policy = "Always"
          env {
            #inject the test id to service name for unique App Signals metrics
            name = "OTEL_SERVICE_NAME"
            value = "sample-application-${var.test_id}"
          }
          env {
            name = "RDS_MYSQL_CLUSTER_CONNECTION_URL"
            value = "jdbc:mysql://${var.rds_mysql_cluster_endpoint}:3306/information_schema"
          }
          env {
            name = "RDS_MYSQL_CLUSTER_USERNAME"
            value = var.rds_mysql_cluster_username
          }
          env {
            name = "RDS_MYSQL_CLUSTER_PASSWORD"
            value = var.rds_mysql_cluster_password
          }
          port {
            container_port = 8080
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "sample_app_service" {
  depends_on = [ kubernetes_deployment.sample_app_deployment ]

  metadata {
    name = "sample-app-service"
    namespace = var.test_namespace
  }
  spec {
    type = "NodePort"
    selector = {
        app = "sample-app"
    }
    port {
      protocol = "TCP"
      port = 8080
      target_port = 8080
      node_port = 30100
    }
  }
}

# Set up the remote service

resource "kubernetes_deployment" "sample_remote_app_deployment" {

  metadata {
    name      = "sample-r-app-deployment-${var.test_id}"
    namespace = var.test_namespace
    labels    = {
      app = "remote-app"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "remote-app"
      }
    }
    template {
      metadata {
        labels = {
          app = "remote-app"
        }
        annotations = {
          # these annotations allow for OTel Java instrumentation
          "instrumentation.opentelemetry.io/inject-java" = "true"
        }
      }
      spec {
        service_account_name = var.service_account_aws_access
        container {
          name = "back-end"
          image = var.sample_remote_app_image
          image_pull_policy = "Always"
          port {
            container_port = 8080
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "sample_remote_app_service" {
  depends_on = [ kubernetes_deployment.sample_remote_app_deployment ]

  metadata {
    name = "sample-remote-app-service"
    namespace = var.test_namespace
  }
  spec {
    type = "NodePort"
    selector = {
      app = "remote-app"
    }
    port {
      protocol = "TCP"
      port = 8080
      target_port = 8080
      node_port = 30101
    }
  }
}

resource "kubernetes_deployment" "traffic_generator" {
  metadata {
    name = "traffic-generator"
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
          name  = "traffic-generator"
          image = "${var.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/e2e-test-resource:traffic-generator"
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