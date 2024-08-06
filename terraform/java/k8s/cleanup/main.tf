

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
      echo "LOG: Deleting helm-charts repo from environment"
      [ ! -e helm-charts ] || sudo rm -r helm-charts

      # Delete sample app resources
      echo "LOG: Deleting sample app namespace"
      kubectl delete namespace sample-app-namespace
      echo "LOG: Deleting sample app deployment files"
      [ ! -e frontend-service-depl.yaml ] || rm frontend-service-depl.yaml
      [ ! -e remote-service-depl.yaml ] || rm remote-service-depl.yaml
      sleep 10

      # Print cluster state when done clean up procedures
      echo "LOG: Printing cluster state after cleanup"
      kubectl get pods -A

      # Delete ssm parameter for main and remote service ip
      aws ssm delete-parameter --name main-service-ip-${var.test_id}
      aws ssm delete-parameter --name remote-service-ip-${var.test_id}
      EOF
    ]
  }
}