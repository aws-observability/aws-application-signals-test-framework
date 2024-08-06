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

resource "null_resource" "cleanup" {
  connection {
    type        = "ssh"
    user        = var.user
    private_key = var.ssh_key
    host        = var.host
  }


  provisioner "remote-exec" {
    inline = [
      <<-EOF
      # Allow terraform to fail any of the following steps without exiting
      set +e

      # Uninstall the operator and remove the repo from the EC2 instance
      echo "LOG: Uninstalling CloudWatch Agent Operator"
      helm uninstall --debug --namespace amazon-cloudwatch amazon-cloudwatch-operator --ignore-not-found
      echo "LOG: Deleting Helm Charts repo from environment"
      [ ! -e helm-charts ] || sudo rm -r helm-charts

      # Delete sample app resources
      echo "LOG: Deleting sample app namespace"
      kubectl delete namespace python-sample-app-namespace
      echo "LOG: Deleting sample app deployment files"
      [ ! -e python-frontend-service-depl.yaml ] || rm python-frontend-service-depl.yaml
      [ ! -e python-remote-service-depl.yaml ] || rm python-remote-service-depl.yaml
      sleep 10

      # Print cluster state when done clean up procedures
      echo "LOG: Printing cluster state after cleanup"
      kubectl get pods -A

      # Delete ssm parameter for main and remote service ip
      aws ssm delete-parameter --name python-main-service-ip-${var.test_id}
      aws ssm delete-parameter --name python-remote-service-ip-${var.test_id}

      EOF
    ]
  }
}