import boto3
from botocore.exceptions import ClientError
from datetime import datetime, timezone, timedelta
import time

client = boto3.client('apigateway')

def delete_api_with_retries(client, api_id, retries=5):
    """Deletes an API with retries and exponential backoff."""
    delay = 10
    for attempt in range(retries):
        try:
            client.delete_rest_api(restApiId=api_id)
            print(f"API {api_id} deleted successfully. Sleeping for 32 seconds...")
            time.sleep(32)
            return
        except ClientError as e:
            if e.response['Error']['Code'] == 'TooManyRequestsException':
                print(f"Rate limit exceeded. Retrying in {delay} seconds (Attempt {attempt + 1}/{retries})...")
                time.sleep(delay)
                delay *= 2  # Exponential backoff
            else:
                print(f"Error deleting API {api_id}: {e}")
                raise  # Re-raise other exceptions
    print(f"Failed to delete API {api_id} after {retries} attempts.")

def delete_old_api_gateways(hours_old=3, batch_size=5):
    """Deletes API Gateways older than the specified hours in batches."""
    now = datetime.now(timezone.utc)  # Ensure `now` is timezone-aware
    cutoff_time = now - timedelta(hours=hours_old)

    print(f"Cutoff time: {cutoff_time}")

    # Fetch all APIs
    apis = client.get_rest_apis()
    batch_counter = 0

    for api in apis.get('items', []):
        created_date = api.get('createdDate')  # This is usually UTC already
        if created_date and isinstance(created_date, datetime):
            # Ensure `created_date` is timezone-aware
            created_date = created_date.astimezone(timezone.utc)

            api_id = api['id']
            api_name = api.get('name', 'Unnamed API')
            if "AdotLambda" in api_name and "SampleApp" in api_name and created_date < cutoff_time:
                print(f"Preparing to delete API: {api_name} (ID: {api_id}), created at {created_date}")

                # Attempt to delete the API with retries
                delete_api_with_retries(client, api_id)

                batch_counter += 1

                # Pause after every batch
                if batch_counter % batch_size == 0:
                    print("Pausing for 2 minutes to avoid rate-limiting...")
                    time.sleep(120)
        else:
            print("Invalid or missing createdDate for API:", api)

if __name__ == "__main__":
    delete_old_api_gateways()