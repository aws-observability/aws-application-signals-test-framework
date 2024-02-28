# Demo Sample App Updating Guide

## Introduction:

The python sample app is used to perform E2E testing on cloudwatch, cloudwatch operator and adot repository. If any changes need to be made on the demo sample app, the following steps should be taken.

## EKS Use Case: Uploading to ECR

### Build the sample app locally:


### Steps to update image:
1. Login to the testing account
2. Create a new ECR repository if there's no existing one.
2. Login to ECR Repository: `aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin {REPOSITORY}`.


## EC2 Use Case: Building the JAR Files
