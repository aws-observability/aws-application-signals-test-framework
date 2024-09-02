import json
import os
import logging

import boto3
from _datetime import datetime, timedelta, timezone
from typing import List

INSTANCE_STATE_RUNNING = 'running'
K8S_INSTANCE_NAME_PREFIX = 'k8s-'
K8S_KEYNAME_PREFIX = 'k8s-'
K8S_ENDPOINT_SECRET_NAME_SUBSTRING = '-k8s-master-node-endpoint'
K8S_ENDPOINT_TEMPORARY_STORAGE_SECRET_NAME_SUBSTRING = '-temporary-storage'

# Create an EC2 client
session = boto3.Session()
ec2 = session.client('ec2')
secret_manager = session.client('secretsmanager')

# configure logging
logging.basicConfig(level=logging.INFO)

def _get_all_instances_by_filter(filters: List[dict]):
    filtered_instances = []

    try:
        # Create a paginator since there can a large number of instances and the response can be paginated
        paginator = ec2.get_paginator('describe_instances')
        # Create a PageIterator from the Paginator with the filter applied
        page_iterator = paginator.paginate(Filters=filters)
        # Iterate through each page and collect all running instances
        for page in page_iterator:
            for reservation in page['Reservations']:
                for instance in reservation['Instances']:
                    filtered_instances.append(instance)
    except Exception as e:
        logging.error(f"Error describing instances: {e}")

    return filtered_instances

def _prepare_report_and_upload(k8s_instances_to_terminate) -> bool:
    json_data = json.dumps({
        "k8sInstances": k8s_instances_to_terminate
    }, default=str)
    # save as a json file with timestamp
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    filename = f"report-k8s-cluster-to-clean-{timestamp}.json"
    with open(filename, "w") as f:
        f.write(json_data)

    try:
        # upload to s3 bucket
        s3 = boto3.client('s3')
        s3.upload_file(filename, os.environ.get("S3_REPORTS_BUCKET", ""), filename)
        # delete the local file
        os.remove(filename)
    except Exception as e:
        logging.error(f"Error uploading file to S3: {e}")
        return False
    return True

def _get_k8s_cluster_instance_in_use():
    # Get list of all secrets
    secrets = []

    # Paginate through the list_secrets results
    paginator = secret_manager.get_paginator('list_secrets')

    for page in paginator.paginate():
        secrets.extend(page['SecretList'])

    # Store k8s cluster currently being used by canary here
    k8s_cluster_instance_in_use = []
    # Loop through secrets and find ones with K8S_ENDPOINT_SECRET_NAME_SUBSTRING in the name
    for secret in secrets:
        secret_name = secret['Name']
        if secret_name.endswith(K8S_ENDPOINT_SECRET_NAME_SUBSTRING):
            try:
                # Get the secret value
                response = secret_manager.get_secret_value(SecretId=secret_name)
                secret_value = response.get('SecretString', None)
                if secret_value:
                    instance_id = find_instance_id_by_ip(secret_value)
                    if instance_id:
                        k8s_cluster_instance_in_use.append(instance_id)

            except Exception as e:
                logging.info(f"Failed to retrieve secret {e}")

        if secret_name.endswith(K8S_ENDPOINT_SECRET_NAME_SUBSTRING + K8S_ENDPOINT_TEMPORARY_STORAGE_SECRET_NAME_SUBSTRING):
            try:
                # Get the secret value
                response = secret_manager.get_secret_value(SecretId=secret_name)
                secret_value = response.get('SecretString', None)
                if secret_value:
                    instance_id = find_instance_id_by_ip(secret_value)
                    if instance_id and not is_instance_older_than_40_days(instance_id):
                        k8s_cluster_instance_in_use.append(instance_id)

            except Exception as e:
                logging.info(f"Failed to retrieve secret {e}")

    return k8s_cluster_instance_in_use

# Check if an instance is older than 40 days
def is_instance_older_than_40_days(instance_id):
    response = ec2.describe_instances(InstanceIds=[instance_id])

    # Extract the launch time of the instance
    launch_time = response['Reservations'][0]['Instances'][0]['LaunchTime']

    # Calculate the age of the instance
    current_time = datetime.now(timezone.utc)
    instance_age = current_time - launch_time

    # Check if the instance is older than 40 days
    return instance_age > timedelta(days=40)

def find_instance_id_by_ip(ip_address):
    # Describe all instances and filter by the given public IP address
    try:
        response = ec2.describe_instances(
            Filters=[
                {'Name': 'ip-address', 'Values': [ip_address]}
            ]
        )

        for reservation in response.get('Reservations', []):
            for instance in reservation.get('Instances', []):
                return instance['InstanceId']
    except Exception as e:
        logging.info(f"Failed to find instance for IP '{ip_address}': {e}")

    return None

def _is_k8s_cluster_instance(instance):
    tags = instance.get('Tags', [])
    if 'Name' in tags and tags['Name'].startswith(K8S_INSTANCE_NAME_PREFIX):
        return True
    if instance.get('KeyName', '').startswith(K8S_KEYNAME_PREFIX):
        return True
    return False

def _get_k8s_instances_to_terminate():
    # Get all the running instances
    logging.info("Start scanning instances")
    running_filter = [{'Name': 'instance-state-name', 'Values': [INSTANCE_STATE_RUNNING]}]
    running_instances = _get_all_instances_by_filter(filters=running_filter)
    logging.info(f"{len(running_instances)} instances are running.")

    # Filter instances that have been running for more than 40 days
    logging.info("Filtering instances that have been running for more than 40 days")
    current_time = datetime.now(timezone.utc)
    time_threshold = timedelta(days=1)
    min_launch_time = current_time - time_threshold
    instances_running_more_than_one_day = []

    for instance in running_instances:
        launch_time = instance['LaunchTime']
        if launch_time < min_launch_time:
            instances_running_more_than_one_day.append(instance)
    logging.info(f"{len(instances_running_more_than_one_day)} instances have been running for more than one day.")

    logging.info("Filtering instances that should not be terminated based on conditions")
    instances_to_terminate = []
    # Get k8s cluster that are being used by canary
    k8s_cluster_in_use = _get_k8s_cluster_instance_in_use()
    for instance in instances_running_more_than_one_day:
        if (_is_k8s_cluster_instance(instance) and not (instance['InstanceId'] in k8s_cluster_in_use)):
            instances_to_terminate.append(instance)

    logging.info(f"{len(instances_to_terminate)} instances will be terminated.")

    return instances_to_terminate

def _terminate_instances(instances_to_terminate):
    # Terminate the instances
    instance_ids = [instance['InstanceId'] for instance in instances]
    try:
        response = ec2.terminate_instances(InstanceIds=instance_ids)
        logging.info("===== Response for terminate instances request =====")
        logging.info(response)
    except Exception as e:
        logging.info(f"Error terminating instances: {e}")


if __name__ == '__main__':
    k8s_instances = _get_k8s_instances_to_terminate()

    if len(k8s_instances) == 0:
        logging.info("No resource to clean up")
        exit(0)

    report_successful = _prepare_report_and_upload(k8s_instances)
    if not report_successful:
        logging.error("Failed to prepare report and upload. Aborting resource clean up.")
        exit(1)

#     if len(k8s_instances) > 0:
#         logging.info("Terminating K8s instances...")
#         _terminate_k8s_instances(k8s_instances)
