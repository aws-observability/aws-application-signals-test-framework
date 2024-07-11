import boto3
from _datetime import datetime, timedelta, timezone
from typing import List

INSTANCE_STATE_RUNNING = 'running'
EKS_CLUSTER_SECURITY_GROUP_PREFIX = 'eks-cluster-sg-'
K8S_INSTANCE_NAME_PREFIX = 'k8s-'
K8S_KEYNAME_PREFIX = 'k8s'
TAG_DO_NOT_DELETE = 'do-not-delete'


def _get_instances_to_terminate():
    # Get all the running instances
    running_filter = [{'Name': 'instance-state-name', 'Values': [INSTANCE_STATE_RUNNING]}]
    running_instances = _get_all_instances_by_filter(filters=running_filter)

    # Filter instances that have been running for more than 3 hours
    current_time = datetime.now(timezone.utc)
    time_threshold = timedelta(hours=3)
    min_launch_time = current_time - time_threshold
    instances_running_more_than_3hrs = []
    for instance in running_instances:
        launch_time = instance['LaunchTime']
        if launch_time < min_launch_time:
            instances_running_more_than_3hrs.append(instance)

    instances_to_terminate = []
    for instance in instances_running_more_than_3hrs:
        if (not _is_eks_cluster_instance(instance)
                and not _is_k8s_cluster_instance(instance)
                and not _is_tagged_do_not_delete(instance)):
            instances_to_terminate.append(instance)

    return instances_to_terminate


def _get_all_instances_by_filter(filters: List[dict]):
    # Create an EC2 client
    session = boto3.Session()
    ec2 = session.client('ec2')

    # Create a paginator
    paginator = ec2.get_paginator('describe_instances')

    # Create a PageIterator from the Paginator with the filter applied
    page_iterator = paginator.paginate(Filters=filters)

    # Iterate through each page and collect all running instances
    filtered_instances = []
    for page in page_iterator:
        for reservation in page['Reservations']:
            for instance in reservation['Instances']:
                filtered_instances.append(instance)

    return filtered_instances


def _is_eks_cluster_instance(instance):
    security_groups = instance.get('SecurityGroups', [])
    if any(group['GroupName'].startswith(EKS_CLUSTER_SECURITY_GROUP_PREFIX) for group in security_groups):
        return True
    return False


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


if __name__ == '__main__':
    instances = _get_instances_to_terminate()
    print("Instance Count: " + str(len(instances)))
    for i in instances:
        print(i['KeyName'])
