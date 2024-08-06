import json
import os
import logging

import boto3
from _datetime import datetime, timedelta, timezone
from typing import List

INSTANCE_STATE_RUNNING = 'running'
EKS_CLUSTER_SECURITY_GROUP_PREFIX = 'eks-cluster-sg-'
K8S_INSTANCE_NAME_PREFIX = 'k8s-'
K8S_KEYNAME_PREFIX = 'k8s-'
TAG_DO_NOT_DELETE = 'do-not-delete'

# Create an EC2 client
session = boto3.Session()
ec2 = session.client('ec2')
autoscaling = session.client('autoscaling')

# configure logging
logging.basicConfig(level=logging.INFO)

def _get_autoscaling_groups_to_delete():
    logging.info("Start scanning autoscaling group...")

    current_time = datetime.now(timezone.utc)
    time_threshold = current_time - timedelta(hours=3)
    groups_to_delete = []

     # Initialize the paginator
    paginator = autoscaling.get_paginator('describe_auto_scaling_groups')

    # Iterate through each page of results
    for page in paginator.paginate():
        auto_scaling_groups = page['AutoScalingGroups']
        for asg in auto_scaling_groups:
            asg_name = asg['AutoScalingGroupName']
            tags = asg['Tags']

            eks_tag_present = any(tag['Key'] == 'eks:cluster-name' for tag in tags)
            if eks_tag_present:
                logging.info(f"Skipping autoscaling group with 'eks:cluster-name' tag: {asg_name}.")
                continue

            if not _is_active(asg):
                logging.info(f"Skipping autoscaling group {asg_name} with terminating instances.")
                continue

            logging.info(f"autoscaling group {asg_name} is active.")

            creation_time = asg['CreatedTime']
            if creation_time < time_threshold:
                print(f"Autoscaling group: {asg_name} will be deleted.")
                groups_to_delete.append(asg)
    
    logging.info(f"{len(groups_to_delete)} autoscaling groups are active for more than 3 hours.")

    return groups_to_delete


def _delete_autoscaling_groups(auto_scaling_groups):
    for asg in auto_scaling_groups:
        try:
            asg_name = asg['AutoScalingGroupName']
            response = autoscaling.delete_auto_scaling_group(AutoScalingGroupName=asg_name, ForceDelete=True)
            logging.info("===== Response for delete autoscaling group request =====")
            logging.info(response)
        except Exception as e:
            logging.info(f"Error deleting groups: {e}")

def _is_active(asg):
    for instance in asg['Instances']:
        if instance['LifecycleState'] in [
            'Terminating', 'Terminating:Wait', 'Terminating:Proceed'
        ]:
            return False
    return True


def _get_instances_to_terminate():
    # Get all the running instances
    logging.info("Start scanning instances")
    running_filter = [{'Name': 'instance-state-name', 'Values': [INSTANCE_STATE_RUNNING]}]
    running_instances = _get_all_instances_by_filter(filters=running_filter)
    logging.info(f"{len(running_instances)} instances are running.")

    # Filter instances that have been running for more than 3 hours
    logging.info("Filtering instances that have been running for more than 3 hours")
    current_time = datetime.now(timezone.utc)
    time_threshold = timedelta(hours=3)
    min_launch_time = current_time - time_threshold
    instances_running_more_than_3hrs = []
    for instance in running_instances:
        launch_time = instance['LaunchTime']
        if launch_time < min_launch_time:
            instances_running_more_than_3hrs.append(instance)
    logging.info(f"{len(instances_running_more_than_3hrs)} instances have been running for more than 3 hours.")

    logging.info("Filtering instances that should not be terminated based on conditions")
    instances_to_terminate = []
    for instance in instances_running_more_than_3hrs:
        if (not _is_k8s_cluster_instance(instance) and not _is_tagged_do_not_delete(instance)):
            group_name = _get_associated_autoscaling_group_name(instance)
            if group_name != None:
                logging.info(f"Instance {instance['InstanceId']} is associated with autoscaling group {group_name}, skip the termination.")
            else:
                instances_to_terminate.append(instance)

    logging.info(f"{len(instances_to_terminate)} instances will be terminated.")

    return instances_to_terminate


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


def _is_k8s_cluster_instance(instance):
    tags = instance.get('Tags', [])
    if 'Name' in tags and tags['Name'].startswith(K8S_INSTANCE_NAME_PREFIX):
        return True
    if instance.get('KeyName', '').startswith(K8S_KEYNAME_PREFIX):
        return True
    return False


def _is_tagged_do_not_delete(instance):
    tags = instance.get('Tags', [])
    if TAG_DO_NOT_DELETE in tags:
        return True
    return False

def _get_associated_autoscaling_group_name(instance):
    tags = instance.get('Tags', [])
    asg_tag = next((tag for tag in tags if tag['Key'] == 'aws:autoscaling:groupName'), None)
    if asg_tag is None:
        return None
    return asg_tag['Value']

def _prepare_report_and_upload(groups_to_delete, instances_to_terminate) -> bool:
    json_data = json.dumps({
        "autoscalingGroups": groups_to_delete,
        "standaloneInstances": instances_to_terminate
    }, default=str)
    # save as a json file with timestamp
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    filename = f"report-resources-to-clean-{timestamp}.json"
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
    groups = _get_autoscaling_groups_to_delete()
    instances = _get_instances_to_terminate()
    
    if len(groups) == 0 and len(instances) == 0:
        logging.info("No resource to clean up")
        exit(0)

    report_successful = _prepare_report_and_upload(groups, instances)
    if not report_successful:
        logging.error("Failed to prepare report and upload. Aborting resource clean up.")
        exit(1)

    if len(groups) > 0:
        logging.info("Deleting autoscaling groups...")
        _delete_autoscaling_groups(groups)

    if len(instances) > 0:
        logging.info("Terminating instances...")
        _terminate_instances(instances)
