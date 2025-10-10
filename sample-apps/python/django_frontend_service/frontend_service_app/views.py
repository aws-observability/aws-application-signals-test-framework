## Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
## SPDX-License-Identifier: Apache-2.0
import logging
import os
import base64
import threading
import time

import boto3
import pymysql
import requests
import schedule
from django.http import HttpResponse, JsonResponse
from opentelemetry import trace, metrics
from opentelemetry.trace.span import format_trace_id
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter as HTTPMetricExporter
from opentelemetry.sdk.metrics.export import ConsoleMetricExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.metrics import Observation
import random

logger = logging.getLogger(__name__)
test_gauge_memory = 512.0 #global variable for test gauge

# Initialize custom OTEL metrics export pipeline - OTLP approach (OTEL/Span export 1) Agent based
custom_resource = Resource.create({
        "service.name": os.getenv("OTEL_SERVICE_NAME", "python-sample-application"),
        "deployment.environment.name": "ec2:default",
        })
custom_otlp_exporter = OTLPMetricExporter(
    endpoint="http://localhost:4317",
    insecure=True
)
custom_otlp_reader = PeriodicExportingMetricReader(
    exporter=custom_otlp_exporter,
    export_interval_millis=5000
)

# Initialize Console exporter - Direct output approach (OTEL export 2) Custom export pipeline
custom_console_exporter = ConsoleMetricExporter()

custom_console_reader = PeriodicExportingMetricReader(
    exporter=custom_console_exporter,
    export_interval_millis=5000
)

# Create meter provider with both exporters Python version of 'SdkMeterProvider.builder().setResource(resource).registerMetricReader(metricReader).build()'
custom_meter_provider = MeterProvider(
    resource=custom_resource,
    metric_readers=[custom_otlp_reader, custom_console_reader]
)


# Initialize counters/meters using custom meter provider. Python version of 'meterProvider.get("myMeter")'
custom_meter = custom_meter_provider.get_meter("custom-metrics") #Create custom_meter
custom_export_counter = custom_meter.create_counter("custom_export_counter", description="Total requests") #Create custom exporter counter
test_histogram = custom_meter.create_histogram("test_histogram", description="Request payload size", unit="bytes")  #Create histogram
 #Create gauge
test_gauge = custom_meter.create_observable_gauge(
    name="test_gauge",
    description="test gauge memory",
    unit="MB",
    callbacks=[lambda: [Observation(test_gauge_memory, {})]]
)

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
    # Setup Span Attributes And Initialize Counter/Gauge/Histogram To Recieve Custom Metrics
    global test_gauge_memory #Call memory variable into api to be updated

    start_time = time.time() #Begin histogram
    custom_export_counter.add(1, {"operation.type": "custom_export_1"})  # Custom export
    test_histogram.record(random.randint(100, 1000), {"operation.type": "histogram"}) #Record histogram
    test_gauge_memory = random.uniform(400.0, 800.0) #Call gauge

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
