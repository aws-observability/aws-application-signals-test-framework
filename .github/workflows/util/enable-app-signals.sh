#!/usr/bin/env bash

cd "$(dirname "$0")"

CLUSTER_NAME=$1
REGION=$2
NAMESPACE=${3:-default}
echo "Enabling Application Signals for EKS Cluster ${CLUSTER_NAME} in ${REGION} for namespace ${NAMESPACE}"

# Check if the current context points to the new cluster in the correct region
kub_config=$(kubectl config current-context)
if [[ $kub_config != *"$CLUSTER_NAME"* ]] || [[ $kub_config != *"$REGION"* ]]; then
    echo "Your current cluster context is not set to $CLUSTER_NAME $REGION. Please switch to the correct context first before running this script"
    exit 1
fi

check_if_step_failed_and_exit() {
  if [ $? -ne 0 ]; then
    echo $1
    exit 1
  fi
}

check_if_loop_failed_and_exit() {
  if [ $1 -ne 0 ]; then
    echo $2
    exit 1
  fi
}

# Create service linked role in the account
aws iam create-service-linked-role --aws-service-name application-signals.cloudwatch.amazonaws.com

# Enable OIDC to allow IAM role authN/Z with service account
eksctl utils associate-iam-oidc-provider --cluster ${CLUSTER_NAME} --region ${REGION} --approve
check_if_step_failed_and_exit "There was an error enabling the OIDC, exiting"

# Create Service Account with the proper IAM permissions
echo "Creating ServiceAccount"
eksctl create iamserviceaccount \
      --name cloudwatch-agent \
      --namespace amazon-cloudwatch \
      --cluster ${CLUSTER_NAME} \
      --region ${REGION} \
      --attach-policy-arn arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess \
      --attach-policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy \
      --approve \
      --override-existing-serviceaccounts
check_if_step_failed_and_exit "There was an error creating the ServiceAccount, exiting"


# Install amazon-cloudwatch-observability addon
echo "Checking amazon-cloudwatch-observability add-on"
result=$(aws eks describe-addon --addon-name amazon-cloudwatch-observability --cluster-name ${CLUSTER_NAME} --region ${REGION} 2>&1)
echo "${result}"

if [[ "${result}" == *"No addon: "* ]];  then
    # Install CloudWatch operator
    echo "Installing CloudWatch operator"
    kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-agent-kubernetes-monitoring/main/kubernetes-manifests/cloudwatch-agent-operator.yaml
    check_if_step_failed_and_exit "There was an error installing CloudWatch operator, exiting"

    # Update the operator image
    kubectl set image deployment/cloudwatch-agent-operator \
      cloudwatch-agent-operator=public.ecr.aws/m2t4f1b8/lisaguo-test-cwa-operator:latest -n amazon-cloudwatch
    check_if_step_failed_and_exit "There was an error updating the CloudWatch operator image, exiting"

    echo "CloudWatch operator installation complete"
else
  aws eks delete-addon --cluster-name ${CLUSTER_NAME} --addon-name amazon-cloudwatch-observability --region ${REGION}
  # Install CloudWatch operator
    echo "Installing CloudWatch operator"
    kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-agent-kubernetes-monitoring/main/kubernetes-manifests/cloudwatch-agent-operator.yaml
    check_if_step_failed_and_exit "There was an error installing CloudWatch operator, exiting"

      # Update the operator image
    kubectl set image deployment/cloudwatch-agent-operator \
    cloudwatch-agent-operator=public.ecr.aws/m2t4f1b8/lisaguo-test-cwa-operator:latest -n amazon-cloudwatch
    check_if_step_failed_and_exit "There was an error updating the CloudWatch operator image, exiting"

    echo "CloudWatch operator installation complete"
fi

if [ -z "${REGION}" ]
then
    echo "Region set to us-west-2"
    REGION="us-west-2"
fi

check_if_step_failed_and_exit "There was an error enabling application signals, exiting"