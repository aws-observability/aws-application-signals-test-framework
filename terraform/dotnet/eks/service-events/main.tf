# ------------------------------------------------------------------------
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
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
  # Matches the other Service Events cells. The CloudWatch Agent derives the Service Events log
  # group from service.name, so this is also what /aws/service-events/<name> resolves to. Note the
  # non-Service-Events .NET EKS module uses "dotnet-application-" instead; the Service Events
  # convention is the one the validators and the log group depend on.
  service_name   = "dotnet-sample-application-${var.test_id}"
  log_group_name = "/aws/service-events/${local.service_name}"
}

# Each run emits into a run-unique Service Events log group. Left to the CW agent these groups are
# created with never-expire retention and outlive the test, accumulating one orphaned group per run.
# Managing the group here gives it a one-day retention and makes `terraform destroy` remove it, so
# even a failed destroy caps storage at a day.
#
# The guarantee is weaker here than on EC2. There, destroying the instance also kills the CW agent
# that would recreate the group. On EKS the agent is a cluster-wide daemonset installed by
# enable-app-signals.sh and outlives this module, so a late flush after the pod is gone can
# recreate the group. The one-day retention is what actually bounds the leak in that case.
resource "aws_cloudwatch_log_group" "service_events" {
  name              = local.log_group_name
  retention_in_days = 1

  tags = {
    Name = "service-events-${var.test_id}"
  }
}

# Single instrumented frontend. Unlike the default .NET EKS cell there is no remote service:
# Service Events emits autonomously from the frontend, so only its own routes need driving.
resource "kubernetes_deployment_v1" "dotnet_app_deployment" {
  metadata {
    name      = "dotnet-app-deployment-${var.test_id}"
    namespace = var.test_namespace
    labels = {
      app = "dotnet-app"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "dotnet-app"
      }
    }
    template {
      metadata {
        labels = {
          app = "dotnet-app"
        }
        annotations = {
          # Marks the pod for ADOT injection by the amazon-cloudwatch-observability operator's
          # mutating webhook. Injection happens at pod-creation time only, so a pod that already
          # exists when the operator is installed has to be recreated to pick it up.
          "instrumentation.opentelemetry.io/inject-dotnet" = "true"
        }
      }
      spec {
        service_account_name = var.service_account_aws_access
        container {
          name              = "back-end"
          image             = var.dotnet_app_image
          image_pull_policy = "Always"

          # Deliberately no ASPNETCORE_URLS. The image defaults to http://+:8080, which is what
          # makes the pod reachable at <podIP>:8080. The EC2 cell binds to loopback because its
          # traffic generator runs on the same host; here the generator is a separate pod, so
          # binding to loopback would make the app unreachable and every validator would fail.

          env {
            name  = "OTEL_SERVICE_NAME"
            value = local.service_name
          }
          # The templates assert deployment.environment.name, which comes from here rather than
          # from the operator.
          env {
            name  = "OTEL_RESOURCE_ATTRIBUTES"
            value = "service.name=${local.service_name},deployment.environment.name=eks:service-events"
          }
          env {
            name  = "OTEL_AWS_APPLICATION_SIGNALS_RUNTIME_ENABLED"
            value = "false"
          }

          # Service Events is enabled by these env vars, not by the injection annotation. The
          # operator supplies the exporter endpoints and enables Application Signals itself, so
          # unlike the EC2 cell there are no OTEL_EXPORTER_* or OTEL_AWS_OTLP_* settings here.
          # OTEL_AWS_SERVICE_EVENTS_ENABLED is deliberately left unset so this still exercises the
          # bundled-enablement contract.
          env {
            name  = "OTEL_AWS_SERVICE_EVENTS_FUNCTION_INSTRUMENT_ENABLED"
            value = "true"
          }
          env {
            name  = "OTEL_AWS_SERVICE_EVENTS_SAMPLING_MODE"
            value = "always"
          }
          env {
            name  = "OTEL_AWS_SERVICE_EVENTS_PACKAGES_INCLUDE"
            value = var.service_events_packages_include
          }
          env {
            name  = "OTEL_AWS_SERVICE_EVENTS_LATENCY_THRESHOLDS"
            value = var.service_events_latency_thresholds
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

          # Flush cadences. The Service Events MeterProvider runs a fixed 60s periodic reader and
          # does not honor OTEL_METRIC_EXPORT_INTERVAL, so without these a signal can take a full
          # window to surface — and the workflow only sleeps 60s before validating.
          env {
            name  = "OTEL_AWS_SERVICE_EVENTS_ENDPOINT_FLUSH_INTERVAL"
            value = "2000"
          }
          env {
            name  = "OTEL_AWS_SERVICE_EVENTS_FUNCTION_CALL_FLUSH_INTERVAL"
            value = "2000"
          }
          env {
            name  = "OTEL_AWS_SERVICE_EVENTS_INCIDENT_SNAPSHOT_FLUSH_INTERVAL"
            value = "2000"
          }
          # Incident rate limiting is three-layered: per-flush batch dedup, a per-error-signature
          # ceiling per minute, and a global ceiling. The traffic generator replays one identical
          # exception on a loop, so the default ceilings would suppress the snapshots under test.
          env {
            name  = "OTEL_AWS_SERVICE_EVENTS_INCIDENT_SNAPSHOT_MAX_PER_MINUTE"
            value = "1000"
          }
          env {
            name  = "OTEL_AWS_SERVICE_EVENTS_INCIDENT_SNAPSHOT_MAX_SAME_ERROR"
            value = "100"
          }

          port {
            container_port = 8080
          }
        }
      }
    }
  }

  # The app emits into the managed log group. Making the relationship explicit reverses the order on
  # destroy: Terraform removes the pod before deleting the group, so the app cannot emit into a
  # group that is already gone.
  depends_on = [aws_cloudwatch_log_group.service_events]
}

resource "kubernetes_service" "dotnet_app_service" {
  depends_on = [kubernetes_deployment_v1.dotnet_app_deployment]

  metadata {
    name      = "dotnet-app-service"
    namespace = var.test_namespace
  }
  spec {
    type = "NodePort"
    selector = {
      app = "dotnet-app"
    }
    port {
      protocol    = "TCP"
      port        = 8080
      target_port = 8080
      node_port   = 30100
    }
  }
}

# The shared traffic-generator image only knows the default sample app's routes, so its command is
# overridden here to drive the Service Events routes instead — the same set the EC2 cell drives:
#   /success     -> HttpClient call to the app's own /health, giving FunctionCall status=success
#                   and, via the 1ms threshold, the latency IncidentSnapshot at HTTP 200
#   /failed-call -> HttpClient call to a closed port, giving FunctionCall status=error
#   /exception   -> throws, giving the exception IncidentSnapshot and EndpointErrorMetric at 500
# MAIN_ENDPOINT is injected by the workflow once the pod IP is known, so the loop waits for it.
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
          command           = ["sh", "-c"]
          args = [
            <<-EOT
            while [ -z "$MAIN_ENDPOINT" ]; do echo "waiting for MAIN_ENDPOINT"; sleep 5; done
            echo "driving Service Events routes against $MAIN_ENDPOINT"
            while true; do
              wget -q -O /dev/null "http://$MAIN_ENDPOINT/" || true
              wget -q -O /dev/null "http://$MAIN_ENDPOINT/success" || true
              wget -q -O /dev/null "http://$MAIN_ENDPOINT/failed-call" || true
              wget -q -O /dev/null "http://$MAIN_ENDPOINT/exception" || true
              sleep 5
            done
            EOT
          ]
          env {
            name  = "ID"
            value = var.test_id
          }
        }
      }
    }
  }
}
