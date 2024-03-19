

resource "null_resource" "cleanup" {
  connection {
    type        = "ssh"
    user        = var.user
    private_key = var.ssh_key
    host        = var.host
  }

  provisioner "remote-exec" {
    inline = [
      # Allow terraform to fail any of the following steps without exiting
      "set +e",

      # Uninstall the operator and remove the repo from the EC2 instance
      "echo \"LOG: Uninstalling CloudWatch Agent Operator\"",
      "helm uninstall --debug --namespace amazon-cloudwatch amazon-cloudwatch-operator --ignore-not-found",
      "echo \"LOG: Deleting CloudWatch Agent Operator repo from environment\"",
      "[ ! -e amazon-cloudwatch-agent-operator ] || sudo rm -r amazon-cloudwatch-agent-operator",

      # Delete sample app resources
      "echo \"LOG: Deleting sample app namespace\"",
      "kubectl delete namespace sample-app-namespace",
      "echo \"LOG: Deleting sample app deployment files\"",
      "[ ! -e frontend-service-depl.yaml ] || rm frontend-service-depl.yaml",
      "[ ! -e remote-service-depl.yaml ] || rm remote-service-depl.yaml",
      "sleep 10",

      # Print cluster state when done clean up procedures
      "echo \"LOG: Printing cluster state after cleanup\"",
      "kubectl get pods -A",
    ]
  }
}