# Node Demo Sample App Updating Guide

## Introduction:

The node sample app is used to perform E2E testing on cloudwatch, cloudwatch operator and ADOT repository. If any changes need to be made on the demo sample app, the following steps should be taken.

## EKS Use Case: Uploading to ECR

### Automated setup:
Simply run the Node ECR deployment workflow, it will automatically populate the ECRs using the versions on the `main` branch of this repository.

### Build the sample app locally:
run `docker-compose build` to generate two docker images: `nodesampleapp/frontend-service` and `nodesampleapp/remote-service`

## EC2 Use Case

### Automated setup:
Simply run the Node S3 deployment workflow, it will automatically populate the ECRs using the versions on the `main` branch of this repository.

## APIs
The following are the APIs supported:
1. http://${ FRONTEND_SERVICE_IP }:8000/outgoing-http-call/
2. http://${ FRONTEND_SERVICE_IP }:8000/aws-sdk-call?testingId=${ TESTING_ID }/
3. http://${ FRONTEND_SERVICE_IP }:8000/remote-service?ip=${ REMOTE_SERVICE_IP }/
4. http://${ FRONTEND_SERVICE_IP }:8000/client-call/
5. http://${ FRONTEND_SERVICE_IP }:8000/mysql/
