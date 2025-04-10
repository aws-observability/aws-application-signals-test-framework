## Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
## SPDX-License-Identifier: Apache-2.0

#!/bin/bash

IS_BASE_RUN=${1:-false}
FUNCTION_NAME=${2:-none}
SLEEP_TIME_SECONDS=300
TEST_RUNS=${NUM_TEST_RUNS:-20}

echo "Running $TEST_RUNS cold start test iterations"

CW_LOGS_QUERY_START_TIME=$(date +%s)

echo "Sleeping for $SLEEP_TIME_SECONDS seconds to ensure logs are within CloudWatch Insights query timeframe"
sleep "$SLEEP_TIME_SECONDS"

ACTUAL_START_TIME=$(date +%s)
echo "Start time for test run: $ACTUAL_START_TIME"

for i in $(seq 1 "$TEST_RUNS"); do
  if $IS_BASE_RUN; then
      ENV_JSON="{\"Variables\":{\"FOO\":\"BAR_$i\"}}"
  else
      ENV_JSON="{\"Variables\":{\"AWS_LAMBDA_EXEC_WRAPPER\":\"/opt/otel-instrument\",\"FOO\":\"BAR_$i\"}}"
  fi

  echo "Iteration $i: Updating environment variables to simulate cold start"

  # Update environment variables
  aws lambda update-function-configuration \
    --function-name $FUNCTION_NAME \
    --environment "$ENV_JSON" > /dev/null

  # Wait a short time for changes to take effect
  sleep 5

  # Invoke the Lambda function
  echo "Iteration $i: Invoking Lambda function"
  aws lambda invoke --function-name $FUNCTION_NAME --payload '{}' response.json > /dev/null

  # Wait to simulate cold start reset
  echo "Iteration $i: Waiting for cold start reset"
  sleep 5
done

ACTUAL_END_TIME=$(date +%s)
echo "End time for test run: $ACTUAL_END_TIME"
echo "Cold start test completed"

echo "Sleeping for $SLEEP_TIME_SECONDS seconds to ensure logs are within CloudWatch Insights query timeframe"
sleep $SLEEP_TIME_SECONDS

CW_LOGS_QUERY_END_TIME=$(date +%s)

echo "Running CloudWatch Logs Insights query..."

QUERY='fields @timestamp, @message, @initDuration
| filter @message like "REPORT RequestId"
| stats
    count(@initDuration) as Sample_Count,
    avg(@initDuration) as Average_Init_Duration,
    min(@initDuration) as Min_Init_Duration,
    max(@initDuration) as Max_Init_Duration,
    pct(@initDuration, 50) as P50_Init_Duration,
    pct(@initDuration, 90) as P90_Init_Duration,
    pct(@initDuration, 99) as P99_Init_Duration'

# Start the query
QUERY_ID=$(aws logs start-query \
  --log-group-name "/aws/lambda/$FUNCTION_NAME" \
  --start-time "$CW_LOGS_QUERY_START_TIME" \
  --end-time "$CW_LOGS_QUERY_END_TIME" \
  --query-string "$QUERY" \
  --output text)

echo "Query ID: $QUERY_ID"

STATUS="Running"
while [ "$STATUS" = "Running" ]; do
  echo "Waiting for query results..."
  sleep 3
  RESULT=$(aws logs get-query-results --query-id "$QUERY_ID")
  STATUS=$(echo "$RESULT" | jq -r .status)
done

if [ "$STATUS" = "Complete" ]; then
  echo "Query completed. Results:"
  echo "$RESULT"
else
  echo "Query failed with status: $STATUS"
fi

FLATTENED=$(echo "$RESULT" | jq -r '
    .results[0] | 
    map({(.field): .value}) | 
    add | 
    del(.Sample_Count) |
    to_entries | 
    map("\"\(.key)\": \"\(.value)\"") | 
    join(",\n")
')

if $IS_BASE_RUN; then
    echo "$FLATTENED" > ../no_layer_results.txt
    echo "Results saved to no_layer_results.txt"
else
    echo "$FLATTENED" > ../layer_results.txt
    echo "Results saved to layer_results.txt"
fi