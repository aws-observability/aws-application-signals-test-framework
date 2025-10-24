## Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
## SPDX-License-Identifier: Apache-2.0
import logging
import os
import base64
import threading
import time
import random
import boto3
import pymysql
import requests
import schedule
from django.http import HttpResponse, JsonResponse
from opentelemetry import trace, metrics
from opentelemetry.trace.span import format_trace_id
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.semconv.resource import ResourceAttributes

logger = logging.getLogger(__name__)

# Custom export pipeline - runs alongside existing CWAgent & ADOT setup
pipeline_resource = Resource.create({
    "service.name": os.environ['SERVICE_NAME'],
    "deployment.environment.name": os.environ['DEPLOYMENT_ENVIRONMENT_NAME']
})

pipeline_metric_exporter = OTLPMetricExporter(
    endpoint="localhost:4317"
)

pipeline_metric_reader = PeriodicExportingMetricReader(
    exporter=pipeline_metric_exporter,
    export_interval_millis=10000
)

pipeline_meter_provider = MeterProvider(
    resource=pipeline_resource,
    metric_readers=[pipeline_metric_reader]
)

pipeline_meter = pipeline_meter_provider.get_meter("myMeter")


#python equivalent of Meter meter = GlobalOpenTelemetry.getMeter("myMeter"); for custom metrics
meter = metrics.get_meter("myMeter")
agent_based_counter = meter.create_counter("agent_based_counter", unit="1", description="agent export counter")
agent_based_histogram = meter.create_histogram("agent_based_histogram", description="agent export histogram")
agent_based_gauge = meter.create_up_down_counter("agent_based_gauge", unit="1", description="agent export gauge")

custom_pipeline_counter = pipeline_meter.create_counter("custom_pipeline_counter", unit="1", description="pipeline export counter")
custom_pipeline_histogram = pipeline_meter.create_histogram("custom_pipeline_histogram", description="pipeline export histogram")
custom_pipeline_gauge = pipeline_meter.create_up_down_counter("custom_pipeline_gauge", unit="1", description="pipeline export gauge")


should_send_local_root_client_call = False
lock = threading.Lock()
def run_local_root_client_call_recurring_service():
    def runnable_task():
        global should_send_local_root_client_call
        with lock:
            if should_send_local_root_client_call:
                should_send_local_root_client_call = False
                try:
                    response = requests.get("http://local-root-client-call")
                    # Handle the response if needed
                except Exception as e:
                    # Handle exceptions
                    pass

    # Schedule the task to run every 1 second
    schedule.every(1).seconds.do(runnable_task)

    # Run the scheduler in a separate thread
    def run_scheduler():
        while True:
            schedule.run_pending()
            time.sleep(0.1)  # Sleep to prevent high CPU usage

    thread = threading.Thread(target=run_scheduler)
    thread.daemon = True  # Daemonize the thread so it exits when the main thread exits
    thread.start()

run_local_root_client_call_recurring_service()

def healthcheck(request):
    return HttpResponse("healthcheck")

def aws_sdk_call(request):
    
    # Increment counter/histogram
    agent_based_counter.add(1, {"Operation": "counter"})
    agent_based_histogram.record(random.randint(100, 1000), {"Operation": "histogram"})
    agent_based_gauge.add(random.randint(-10, 10), {"Operation": "gauge"})

    custom_pipeline_counter.add(1, {"Operation": "pipeline_counter"})
    custom_pipeline_histogram.record(random.randint(100, 1000), {"Operation": "pipeline_histogram"})
    custom_pipeline_gauge.add(random.randint(-10, 10), {"Operation": "pipeline_gauge"})

    bucket_name = "e2e-test-bucket-name"

    # Add a unique test ID to bucketname to associate buckets to specific test runs
    testing_id = request.GET.get('testingId', None)
    if testing_id is not None:
        bucket_name += "-" + testing_id
    logger.warning("This is a custom log for validation testing")
    s3_client = boto3.client("s3")
    try:
        s3_client.get_bucket_location(
            Bucket=bucket_name,
        )
    except Exception as e:
        # bucket_name does not exist, so this is expected.
        logger.error("Error occurred when trying to get bucket location of: " + bucket_name)
        logger.error("Could not retrieve http request:" + str(e))

    return get_xray_trace_id()

def http_call(request):
    url = "https://www.amazon.com"
    try:
        response = requests.get(url)
        status_code = response.status_code
        logger.info("outgoing-http-call status code: " + str(status_code))
    except Exception as e:
        logger.error("Could not complete http request:" + str(e))
    return get_xray_trace_id()

def downstream_service(request):
    ip = request.GET.get('ip', '')
    ip = ip.replace("/", "")
    url = f"http://{ip}:8001/healthcheck"
    try:
        response = requests.get(url)
        status_code = response.status_code
        logger.info("Remote service call status code: " + str(status_code))
        return get_xray_trace_id()
    except Exception as e:
        logger.error("Could not complete http request to remote service:" + str(e))

    return get_xray_trace_id()

def async_service(request):
    global should_send_local_root_client_call
    # Log the request
    logger.info("Client-call received")
    # Set the condition to trigger the recurring service
    with lock:
        should_send_local_root_client_call = True
    # Return a dummy traceId in the response
    return JsonResponse({'traceId': '1-00000000-000000000000000000000000'})

def get_xray_trace_id():
    span = trace.get_current_span()
    trace_id = format_trace_id(span.get_span_context().trace_id)
    xray_trace_id = f"1-{trace_id[:8]}-{trace_id[8:]}"

    return JsonResponse({"traceId": xray_trace_id})

def mysql(request):
    logger.info("mysql received")

    encoded_password = os.environ["RDS_MYSQL_CLUSTER_PASSWORD"]
    decoded_password = base64.b64decode(encoded_password).decode('utf-8')

    try:
        connection = pymysql.connect(host=os.environ["RDS_MYSQL_CLUSTER_ENDPOINT"],
                                     user=os.environ["RDS_MYSQL_CLUSTER_USERNAME"],
                                     password=decoded_password,
                                     database=os.environ["RDS_MYSQL_CLUSTER_DATABASE"])
        with connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT * FROM tables LIMIT 1;")
    except Exception as e:  # pylint: disable=broad-except
        logger.error("Could not complete http request to RDS database:" + str(e))
    finally:
        return get_xray_trace_id()
