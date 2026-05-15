import json
import os
import logging

import boto3
from _datetime import datetime, timedelta, timezone

E2E_CLUSTER_PREFIX = "e2e-test-"

session = boto3.Session()
ecs = session.client("ecs")

logging.basicConfig(level=logging.INFO)


def _get_clusters_to_delete():
    logging.info("Start scanning ECS clusters...")

    current_time = datetime.now(timezone.utc)
    time_threshold = current_time - timedelta(hours=3)
    clusters_to_delete = []

    paginator = ecs.get_paginator("list_clusters")
    for page in paginator.paginate():
        for cluster_arn in page["clusterArns"]:
            cluster_name = cluster_arn.split("/")[-1]
            if not cluster_name.startswith(E2E_CLUSTER_PREFIX):
                continue

            services = ecs.list_services(cluster=cluster_arn).get("serviceArns", [])
            if not services:
                logging.info(f"Cluster {cluster_name} has no services, marking for deletion.")
                clusters_to_delete.append({"clusterArn": cluster_arn, "clusterName": cluster_name, "services": []})
                continue

            svc_desc = ecs.describe_services(cluster=cluster_arn, services=services)["services"]
            all_old = True
            for svc in svc_desc:
                created = svc["createdAt"]
                if created > time_threshold:
                    all_old = False
                    break

            if all_old:
                logging.info(f"Cluster {cluster_name} has services older than 3 hours, marking for deletion.")
                clusters_to_delete.append({"clusterArn": cluster_arn, "clusterName": cluster_name, "services": services})

    logging.info(f"{len(clusters_to_delete)} ECS clusters will be deleted.")
    return clusters_to_delete


def _prepare_report_and_upload(clusters_to_delete) -> bool:
    json_data = json.dumps({"ecsClusters": clusters_to_delete}, default=str)
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    filename = f"report-ecs-clusters-to-clean-{timestamp}.json"
    with open(filename, "w") as f:
        f.write(json_data)

    try:
        s3 = boto3.client("s3")
        s3.upload_file(filename, os.environ.get("S3_REPORTS_BUCKET", ""), filename)
        os.remove(filename)
    except Exception as e:
        logging.error(f"Error uploading file to S3: {e}")
        return False
    return True


def _delete_clusters(clusters_to_delete):
    for cluster in clusters_to_delete:
        cluster_arn = cluster["clusterArn"]
        cluster_name = cluster["clusterName"]
        services = cluster["services"]

        try:
            for service_arn in services:
                logging.info(f"Deleting service {service_arn} in cluster {cluster_name}")
                ecs.update_service(cluster=cluster_arn, service=service_arn, desiredCount=0)
                ecs.delete_service(cluster=cluster_arn, service=service_arn, force=True)

            logging.info(f"Deleting cluster {cluster_name}")
            ecs.delete_cluster(cluster=cluster_arn)
        except Exception as e:
            logging.error(f"Error deleting cluster {cluster_name}: {e}")


if __name__ == "__main__":
    clusters = _get_clusters_to_delete()

    if len(clusters) == 0:
        logging.info("No ECS resources to clean up")
        exit(0)

    report_successful = _prepare_report_and_upload(clusters)
    if not report_successful:
        logging.error("Failed to prepare report and upload. Aborting resource clean up.")
        exit(1)

    _delete_clusters(clusters)
