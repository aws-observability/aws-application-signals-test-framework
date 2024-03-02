# Python Demo Sample App Updating Guide

## Introduction:

The python sample app is used to perform E2E testing on cloudwatch, cloudwatch operator and adot repository. If any changes need to be made on the demo sample app, the following steps should be taken.

## EKS Use Case: Uploading to ECR

### Build the sample app locally:
run `docker-compose build` to generate two docker images: `pythonsampleapp/frontend-service` and `pythonsampleapp/remote-service`

### Steps to update image:
1. Login to the testing account
2. Create a new ECR repository if there's no existing one.
3. Login to ECR Repository: `aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin {REPOSITORY}`.
4. tag images and push to repository:
```
docker tag pythonsampleapp/frontend-service:latest ${REPOSITORY_PREFIX}/pythonsampleapp/frontend-service:latest
docker push ${REPOSITORY_PREFIX}/pythonsampleapp/frontend-service:latest
docker tag pythonsampleapp/remote-service:latest ${REPOSITORY_PREFIX}/pythonsampleapp/remote-service:latest
docker push ${REPOSITORY_PREFIX}/pythonsampleapp/remote-service:latest
```


## EC2 Use Case: Building the JAR Files:
1. Compress the folder with: `zip -r python-sample-app.zip .`
2. Login to the testing account
3. Create a new S3 bucket if there's no existing one.
4. upload `python-sample-app.zip` to the bucket


## APIs
The following are the APIs supported:
1. http://${ FRONTEND_SERVICE_IP }:8000/outgoing-http-call/
2. http://${ FRONTEND_SERVICE_IP }:8000/aws-sdk-call/
3. http://${ FRONTEND_SERVICE_IP }:8000/remote-service?ip=${ REMOTE_SERVICE_IP }/
4. http://${ FRONTEND_SERVICE_IP }:8000/client-call/
