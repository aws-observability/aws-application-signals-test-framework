# EKS Terraform Deployment

Deploy the Python Flask sample application to Amazon EKS using Terraform.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform installed
- kubectl installed
- ECR image pushed to your AWS account

## Deployment Instructions

1. **Navigate to the terraform directory:**
   ```bash
   cd infrastructure/eks/terraform
   ```

2. **Copy and customize the variables:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

3. **Initialize Terraform:**
   ```bash
   terraform init
   ```

4. **Plan the deployment:**
   ```bash
   terraform plan
   ```

5. **Deploy the infrastructure:**
   ```bash
   terraform apply
   ```

6. **Configure kubectl:**
   ```bash
   aws eks update-kubeconfig --region us-east-1 --name python-flask-eks-terraform-cluster
   ```

7. **Verify deployment:**
   ```bash
   kubectl get pods
   kubectl get services
   ```

8. **Get LoadBalancer URL:**
   ```bash
   kubectl get service python-flask-eks-terraform-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
   ```

## Clean Up

```bash
terraform destroy
```

## What Gets Deployed

- EKS cluster with Kubernetes 1.30
- Single t3.medium worker node in public subnets
- Python Flask application deployment with traffic generator
- LoadBalancer service to expose the application
- IAM roles with ECR, S3, and SSM permissions
- Access for Admin and ReadOnly AWS roles