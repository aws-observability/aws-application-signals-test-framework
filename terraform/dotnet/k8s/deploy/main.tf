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
      kubectl delete namespace dotnet-sample-app-namespace --ignore-not-found=true
      [ ! -e helm-charts ] || sudo rm -r helm-charts
      [ ! -e dotnet-frontend-service-depl.yaml ] || rm dotnet-frontend-service-depl.yaml
      [ ! -e dotnet-remote-service-depl.yaml ] || rm dotnet-remote-service-depl.yaml

      echo "LOG: Getting latest helm chart release URL"
      latest_version_url=$(curl -s https://api.github.com/repos/aws-observability/helm-charts/releases/182005608 | grep "tarball_url" | cut -d '"' -f 4)
      echo "LOG: The latest helm chart version url is $latest_version_url"
      echo "LOG: Downloading and unpacking the helm chart repo"
      curl -L $latest_version_url -o aws-observability-helm-charts-latest.tar.gz
      mkdir helm-charts
      tar -xvzf aws-observability-helm-charts-latest.tar.gz -C helm-charts
      cd helm-charts/aws-observability-helm-charts*/charts/amazon-cloudwatch-observability

      echo "LOG: Installing CloudWatch Agent Operator using Helm"
      helm upgrade --install --debug --namespace amazon-cloudwatch amazon-cloudwatch-operator ./ --create-namespace --set region=${var.aws_region} --set clusterName=k8s-cluster-${var.test_id}

      # Wait for pods to exist before checking if they're ready
      sleep 60
      kubectl wait --for=condition=Ready pods --all --selector=app.kubernetes.io/name=amazon-cloudwatch-observability -n amazon-cloudwatch --timeout=60s
      kubectl wait --for=condition=Ready pods --all --selector=app.kubernetes.io/name=cloudwatch-agent -n amazon-cloudwatch --timeout=60s

      if [ "${var.repository}" = "amazon-cloudwatch-agent" ]; then
        RELEASE_TESTING_SECRET_NAME=release-testing-ecr-secret
        RELEASE_TESTING_TOKEN=`aws ecr --region=us-west-2 get-authorization-token --output text --query authorizationData[].authorizationToken | base64 -d | cut -d: -f2`
        kubectl delete secret -n amazon-cloudwatch --ignore-not-found $RELEASE_TESTING_SECRET_NAME
        kubectl create secret -n amazon-cloudwatch docker-registry $RELEASE_TESTING_SECRET_NAME \
          --docker-server=https://${var.release_testing_ecr_account}.dkr.ecr.us-west-2.amazonaws.com \
          --docker-username=AWS \
          --docker-password="$${RELEASE_TESTING_TOKEN}"

        kubectl patch serviceaccount cloudwatch-agent -n amazon-cloudwatch -p='{"imagePullSecrets": [{"name": "release-testing-ecr-secret"}]}'
        kubectl delete pods --all -n amazon-cloudwatch
      elif [ "${var.repository}" = "amazon-cloudwatch-agent-operator" ]; then
        RELEASE_TESTING_SECRET_NAME=release-testing-ecr-secret
        RELEASE_TESTING_TOKEN=`aws ecr --region=us-west-2 get-authorization-token --output text --query authorizationData[].authorizationToken | base64 -d | cut -d: -f2`
        kubectl delete secret -n amazon-cloudwatch --ignore-not-found $RELEASE_TESTING_SECRET_NAME
        kubectl create secret -n amazon-cloudwatch docker-registry $RELEASE_TESTING_SECRET_NAME \
          --docker-server=https://${var.release_testing_ecr_account}.dkr.ecr.us-west-2.amazonaws.com \
          --docker-username=AWS \
          --docker-password="$${RELEASE_TESTING_TOKEN}"

        kubectl patch deploy -n amazon-cloudwatch amazon-cloudwatch-observability-controller-manager --type='json' -p='[{"op": "add", "path": "/spec/template/spec/imagePullSecrets", "value": [{"name": "release-testing-ecr-secret"}]}]'
        kubectl delete pods --all -n amazon-cloudwatch
      fi

      if [ "${var.repository}" = "amazon-cloudwatch-agent-operator" ]; then
        kubectl patch deploy -n amazon-cloudwatch amazon-cloudwatch-observability-controller-manager --type='json' -p '[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "${var.patch_image_arn}"}, {"op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Always"}]]'
        kubectl delete pods --all -n amazon-cloudwatch
        sleep 10
        kubectl wait --for=condition=Ready pod --all -n amazon-cloudwatch
      elif [ "${var.repository}" = "amazon-cloudwatch-agent" ]; then
        kubectl patch amazoncloudwatchagents -n amazon-cloudwatch cloudwatch-agent --type='json' -p='[{"op": "replace", "path": "/spec/image", "value": ${var.patch_image_arn}}]'
        kubectl delete pods --all -n amazon-cloudwatch
        sleep 10
        kubectl wait --for=condition=Ready pod --all -n amazon-cloudwatch
      elif [ "${var.repository}" = "aws-otel-dotnet-instrumentation" ]; then
        kubectl patch deploy -n amazon-cloudwatch amazon-cloudwatch-observability-controller-manager --type='json' \
        -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args/4", "value": "--auto-instrumentation-dotnet-image=${var.patch_image_arn}"}]'
        kubectl delete pods --all -n amazon-cloudwatch
        sleep 10
        kubectl wait --for=condition=Ready pod --all -n amazon-cloudwatch
      fi

      # Create sample app namespace
      echo "LOG: Creating sample app namespace"
      kubectl create namespace dotnet-sample-app-namespace

      # Set up secret to pull image with
      echo "LOG: Creating secret to access ECR images"
      ACCOUNT=$(aws sts get-caller-identity --query 'Account' --output text)
      SECRET_NAME=ecr-secret
      TOKEN=`aws ecr --region=${var.aws_region} get-authorization-token --output text --query authorizationData[].authorizationToken | base64 -d | cut -d: -f2`

      echo "LOG: Deleting secret if it exists"
      kubectl delete secret -n dotnet-sample-app-namespace --ignore-not-found $SECRET_NAME

      echo "LOG: Creating secret for pulling sample app ECR"
      kubectl create secret -n dotnet-sample-app-namespace docker-registry $SECRET_NAME \
      --docker-server=https://$ACCOUNT.dkr.ecr.${var.aws_region}.amazonaws.com \
      --docker-username=AWS \
      --docker-password="$${TOKEN}"

      # Deploy sample app
      echo "LOG: Pulling sample app deployment files"
      # cd to ensure everything is downloaded into root directory so cleanup is each
      cd ~
      aws s3api get-object --bucket aws-appsignals-sample-app-prod-us-east-1 --key dotnet-frontend-service-depl-${var.test_id}.yaml dotnet-frontend-service-depl.yaml
      aws s3api get-object --bucket aws-appsignals-sample-app-prod-us-east-1 --key dotnet-remote-service-depl-${var.test_id}.yaml dotnet-remote-service-depl.yaml

      # Patch the staging image if this is running as part of release testing
      if [ "${var.repository}" = "aws-otel-dotnet-instrumentation" ]; then
        RELEASE_TESTING_SECRET_NAME=release-testing-ecr-secret
        kubectl delete secret -n dotnet-sample-app-namespace --ignore-not-found $RELEASE_TESTING_SECRET_NAME
        kubectl create secret -n dotnet-sample-app-namespace docker-registry $RELEASE_TESTING_SECRET_NAME \
          --docker-server=https://${var.release_testing_ecr_account}.dkr.ecr.us-east-1.amazonaws.com \
          --docker-username=AWS \
          --docker-password="$${TOKEN}"

        yq eval '.spec.template.spec.imagePullSecrets += [{"name": "release-testing-ecr-secret"}]' -i dotnet-frontend-service-depl.yaml
        yq eval '.spec.template.spec.imagePullSecrets += [{"name": "release-testing-ecr-secret"}]' -i dotnet-remote-service-depl.yaml
      fi

      echo "LOG: Applying sample app deployment files"
      kubectl apply -f dotnet-frontend-service-depl.yaml
      kubectl apply -f dotnet-remote-service-depl.yaml

      echo "Wait for sample app to be reach ready state"
      sleep 10
      kubectl wait --for=condition=Ready --request-timeout '10m' pod --all -n dotnet-sample-app-namespace

      # Emit main and remote service pod IP
      echo "LOG: Outputting remote service pod IP to SSM using put-parameter API"
      aws ssm put-parameter --region ${var.aws_region} --name dotnet-main-service-ip-${var.test_id} --type String --overwrite --value $(kubectl get pod --selector=app=dotnet-sample-app -n dotnet-sample-app-namespace -o jsonpath='{.items[0].status.podIP}')
      aws ssm put-parameter --region ${var.aws_region} --name dotnet-remote-service-ip-${var.test_id} --type String --overwrite --value $(kubectl get pod --selector=app=dotnet-remote-app -n dotnet-sample-app-namespace -o jsonpath='{.items[0].status.podIP}')

      # Wait a bit more in case the sample apps aren't ready yet
      sleep 30

      # Deploy the traffic generator
      kubectl create deployment -n dotnet-sample-app-namespace traffic-generator \
        --image=$ACCOUNT.dkr.ecr.${var.aws_region}.amazonaws.com/e2e-test-resource:traffic-generator \
        --replicas=1

      # Patch it with ImagePull always policy so that it pulls the latest image from the ECR
      kubectl patch deployment -n dotnet-sample-app-namespace traffic-generator --patch '{"spec": {"template": {"spec": {"containers": [{"name": "e2e-test-resource", "imagePullPolicy": "Always"}]}}}}'
      kubectl patch deployment traffic-generator -n dotnet-sample-app-namespace --type='json' -p='[{"op": "add", "path": "/spec/template/spec/imagePullSecrets", "value": [{"name": "ecr-secret"}]}]'

      # Add the appropriate environment variables to the traffic generator
      kubectl set env -n dotnet-sample-app-namespace deployment/traffic-generator \
      MAIN_ENDPOINT=$(kubectl get pods -n dotnet-sample-app-namespace --selector=app=dotnet-sample-app -o jsonpath='{.items[0].status.podIP}'):8080 \
      REMOTE_ENDPOINT=$(kubectl get pod -n dotnet-sample-app-namespace --selector=app=dotnet-remote-app -o jsonpath='{.items[0].status.podIP}') \
      ID=${var.test_id}

      sleep 10
      EOF
    ]
  }
}
