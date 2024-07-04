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

resource "null_resource" "deploy" {
  connection {
    type        = "ssh"
    user        = var.user
    private_key = var.ssh_key
    host        = var.host
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOF
      # Make the Terraform fail if any step throws an error
      set -e

      # Ensure environment is clean
      echo "LOG: Rerunning cleanup commands in case of cleanup failure in previous run"
      helm uninstall --debug --namespace amazon-cloudwatch amazon-cloudwatch-operator --ignore-not-found
      kubectl delete namespace sample-app-namespace --ignore-not-found=true
      [ ! -e amazon-cloudwatch-agent-operator ] || sudo rm -r amazon-cloudwatch-agent-operator
      [ ! -e frontend-service-depl.yaml ] || rm frontend-service-depl.yaml
      [ ! -e remote-service-depl.yaml ] || rm remote-service-depl.yaml

      # Clone and install operator onto cluster
      echo "LOG: Cloning helm-charts repo"
      git clone https://github.com/aws-observability/helm-charts -q

      cd helm-charts/charts/amazon-cloudwatch-observability/

      echo "LOG: Installing CloudWatch Agent Operator using Helm"
      helm upgrade --install --debug --namespace amazon-cloudwatch amazon-cloudwatch-operator ./ --create-namespace --set region=${var.aws_region} --set clusterName=k8s-cluster-${var.test_id}

      # Wait for pods to exist before checking if they're ready
      sleep 60
      kubectl wait --for=condition=Ready pods --all --selector=app.kubernetes.io/name=amazon-cloudwatch-observability -n amazon-cloudwatch --timeout=60s
      kubectl wait --for=condition=Ready pods --all --selector=app.kubernetes.io/name=cloudwatch-agent -n amazon-cloudwatch --timeout=60s

      # Create sample app namespace
      echo "LOG: Creating sample app namespace"
      kubectl create namespace sample-app-namespace

      # Set up secret to pull image with
      echo "LOG: Creating secret to access ECR images"
      ACCOUNT=$(aws sts get-caller-identity --query 'Account' --output text)
      SECRET_NAME=ecr-secret
      TOKEN=`aws ecr --region=${var.aws_region} get-authorization-token --output text --query authorizationData[].authorizationToken | base64 -d | cut -d: -f2`

      echo "LOG: Deleting secret if it exists"
      kubectl delete secret -n sample-app-namespace --ignore-not-found $SECRET_NAME
      echo "LOG: Creating secret for pulling sample app ECR"
      kubectl create secret -n sample-app-namespace docker-registry $SECRET_NAME \
      --docker-server=https://$ACCOUNT.dkr.ecr.${var.aws_region}.amazonaws.com \
      --docker-username=AWS \
      --docker-password="$${TOKEN}"

      # Deploy sample app
      echo "LOG: Pulling sample app deployment files"

      # cd to ensure everything is downloaded into root directory so cleanup is each
      cd ~
      aws s3api get-object --bucket aws-appsignals-sample-app-prod-us-east-1 --key frontend-service-depl.yaml frontend-service-depl.yaml
      aws s3api get-object --bucket aws-appsignals-sample-app-prod-us-east-1 --key remote-service-depl.yaml remote-service-depl.yaml
      echo "LOG: Applying sample app deployment files"
      kubectl apply -f frontend-service-depl.yaml
      kubectl apply -f remote-service-depl.yaml

      # Expose sample app on port 30100
      echo "LOG: Exposing main sample app on port 30100"
      kubectl expose deployment sample-app-deployment-${var.test_id} -n sample-app-namespace --type="NodePort" --port 8080
      kubectl patch service sample-app-deployment-${var.test_id} -n sample-app-namespace --type='json' --patch='[{"op": "replace", "path": "/spec/ports/0/nodePort", "value":30100}]'

      # Wait for sample app to be reach ready state
      sleep 10
      kubectl wait --for=condition=Ready --request-timeout '5m' pod --all -n sample-app-namespace

      # Emit remote service pod IP
      echo "LOG: Outputting remote service pod IP to SSM using put-parameter API"
      aws ssm put-parameter --region ${var.aws_region} --name remote-service-ip --type String --overwrite --value $(kubectl get pod --selector=app=remote-app -n sample-app-namespace -o jsonpath='{.items[0].status.podIP}')

      EOF
    ]
  }
}
