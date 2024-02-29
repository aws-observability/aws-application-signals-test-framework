from django.http import HttpResponse, JsonResponse
import boto3
import logging
import requests
import schedule
import time
from threading import Thread
from opentelemetry import trace
from opentelemetry.trace.span import format_trace_id

logger = logging.getLogger(__name__)

should_send_local_root_client_call = False
def run_local_root_client_call_recurring_service():
    def runnable_task():
        global should_send_local_root_client_call
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

    thread = Thread(target=run_scheduler)
    thread.daemon = True  # Daemonize the thread so it exits when the main thread exits
    thread.start()

run_local_root_client_call_recurring_service()

def healthcheck(request):
    return HttpResponse("healthcheck")

def aws_sdk_call(request):
    bucket_name = "e2e-test-bucket-name"
    s3_client = boto3.client("s3")

    try:
        s3_client.get_bucket_location(
            Bucket=bucket_name,
        )
    except Exception as e:
        logger.error("Could not retrieve http request:" + str(e))

    return HttpResponse(get_xray_trace_id())

def http_call(request):
    url = "https://www.amazon.com"
    try:
        response = requests.get(url)
        status_code = response.status_code
        logger.info("outgoing-http-call status code: " + str(status_code))
    except Exception as e:
        logger.error("Could not complete http request:" + str(e))
    return HttpResponse(get_xray_trace_id())

def downstream_service(request):
    ip = request.GET.get('ip', '')
    print("ip!!!!!!!!!!!!!")
    print(ip)
    url = f"http://{ip}:8001/health-check"
    try:
        response = requests.get(url)
        status_code = response.status_code
        logger.info("Remote service call status code: " + str(status_code))
        return HttpResponse(get_xray_trace_id())
    except Exception as e:
        logger.error("Could not complete http request to remote service:" + str(e))

    return HttpResponse(get_xray_trace_id())

def async_service(request):
    global should_send_local_root_client_call
    # Log the request
    logger.info("Client-call received")
    # Set the condition to trigger the recurring service
    should_send_local_root_client_call = True
    # Return a dummy traceId in the response
    return JsonResponse({'traceId': '1-00000000-000000000000000000000000'})

def get_xray_trace_id():
    span = trace.get_current_span()
    trace_id = format_trace_id(span.get_span_context().trace_id)
    xray_trace_id = "1-" + trace_id[:8] + "-" + trace_id[8:]

    return "traceId : " + xray_trace_id
