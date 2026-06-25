#!/bin/bash
## Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
## SPDX-License-Identifier: Apache-2.0

# Runs all three cold start performance scenarios against the SAME Lambda
# function in a single invocation:
#   1. Full SDK   (layer attached, standard otel-instrument wrapper)
#   2. Lite SDK   (layer attached, OTEL_AWS_LAMBDA_FAST_START=true)
#   3. No layer   (baseline, instrumentation removed)
#
# Each scenario records its own CloudWatch time window so a single pair of
# sleeps (instead of one pair per scenario) is enough to bracket every run.
#
# Usage: ./lambda-perf-test-all.sh <function-name> <layer-arn>
#   <function-name> : name of the Lambda function to exercise
#   <layer-arn>     : ARN of the SDK layer to (re)attach for the SDK runs

set -euo pipefail

FUNCTION_NAME=${1:-none}
LAYER_ARN=${2:-none}
SLEEP_TIME_SECONDS=300
TEST_RUNS=${NUM_TEST_RUNS:-20}

# Runs TEST_RUNS cold start iterations using the provided environment JSON.
run_iterations() {
  local env_json=$1
  for i in $(seq 1 "$TEST_RUNS"); do
    local iter_env
    iter_env=$(echo "$env_json" | jq -c --arg foo "BAR_$i" '.Variables.FOO = $foo')

    echo "Iteration $i: Updating environment variables to simulate cold start"
    aws lambda update-function-configuration \
      --function-name "$FUNCTION_NAME" \
      --environment "$iter_env" > /dev/null

    sleep 5

    echo "Iteration $i: Invoking Lambda function"
    aws lambda invoke --function-name "$FUNCTION_NAME" --payload '{}' response.json > /dev/null

    echo "Iteration $i: Waiting for cold start reset"
    sleep 5
  done
}

# Runs the CloudWatch Logs Insights init-duration query for a time window and
# writes the flattened result to the given output file.
query_init_duration() {
  local start_time=$1
  local end_time=$2
  local output_file=$3
  local label=$4

  echo "Running CloudWatch Logs Insights query for: $label"

  local query='fields @timestamp, @message, @initDuration
| filter @message like "REPORT RequestId"
| stats
    count(@initDuration) as Sample_Count,
    avg(@initDuration) as Average_Init_Duration,
    min(@initDuration) as Min_Init_Duration,
    max(@initDuration) as Max_Init_Duration,
    pct(@initDuration, 50) as P50_Init_Duration,
    pct(@initDuration, 90) as P90_Init_Duration,
    pct(@initDuration, 99) as P99_Init_Duration'

  local query_id
  query_id=$(aws logs start-query \
    --log-group-name "/aws/lambda/$FUNCTION_NAME" \
    --start-time "$start_time" \
    --end-time "$end_time" \
    --query-string "$query" \
    --output text)

  echo "Query ID: $query_id"

  local status="Running"
  local result=""
  while [ "$status" = "Running" ]; do
    echo "Waiting for query results..."
    sleep 3
    result=$(aws logs get-query-results --query-id "$query_id")
    status=$(echo "$result" | jq -r .status)
  done

  if [ "$status" = "Complete" ]; then
    echo "Query completed for $label. Results:"
    echo "$result"
  else
    echo "Query failed for $label with status: $status"
  fi

  echo "$result" | jq -r '
      .results[0] |
      map({(.field): .value}) |
      add |
      del(.Sample_Count) |
      to_entries |
      map("\"\(.key)\": \"\(.value)\"") |
      join(",\n")
  ' > "$output_file"
  echo "Results saved to $output_file"
}

echo "Running $TEST_RUNS cold start test iterations for all three scenarios"

# --- Run 1: Full SDK (layer attached, standard wrapper) ---
echo "=== Scenario 1: Full SDK ==="
aws lambda update-function-configuration \
  --function-name "$FUNCTION_NAME" \
  --layers "$LAYER_ARN" > /dev/null
sleep 5
FULL_SDK_START=$(date +%s)
run_iterations '{"Variables":{"AWS_LAMBDA_EXEC_WRAPPER":"/opt/otel-instrument"}}'
FULL_SDK_END=$(date +%s)

# --- Run 2: Lite SDK (layer attached, fast start) ---
echo "=== Scenario 2: Lite SDK (Fast Start) ==="
LITE_SDK_START=$(date +%s)
run_iterations '{"Variables":{"AWS_LAMBDA_EXEC_WRAPPER":"/opt/otel-instrument","OTEL_AWS_LAMBDA_FAST_START":"true","OTEL_METRICS_EXPORTER":"none","OTEL_LOGS_EXPORTER":"none"}}'
LITE_SDK_END=$(date +%s)

# --- Run 3: No layer (baseline) ---
echo "=== Scenario 3: No Layer (Baseline) ==="
echo "Removing Lambda layer..."
OUTPUT=$(aws lambda update-function-configuration \
  --function-name "$FUNCTION_NAME" \
  --layers [])
LAYERS=$(echo "$OUTPUT" | jq -r '.Layers | length')
if [ "$LAYERS" -ne 0 ]; then
  echo "::error::Found $LAYERS layer(s) still attached to the function"
  echo "$OUTPUT" | jq -r '.Layers'
  exit 1
fi
echo "✅ Layers successfully removed"
sleep 5
NO_LAYER_START=$(date +%s)
run_iterations '{"Variables":{}}'
NO_LAYER_END=$(date +%s)

echo "All cold start iterations completed"

echo "Sleeping for $SLEEP_TIME_SECONDS seconds to ensure logs are within CloudWatch Insights query timeframe"
sleep "$SLEEP_TIME_SECONDS"

# --- Query each scenario's time window separately ---
query_init_duration "$FULL_SDK_START" "$FULL_SDK_END" "../layer_results.txt" "Full SDK"
query_init_duration "$LITE_SDK_START" "$LITE_SDK_END" "../lite_sdk_results.txt" "Lite SDK"
query_init_duration "$NO_LAYER_START" "$NO_LAYER_END" "../no_layer_results.txt" "No Layer"

echo "All results saved: layer_results.txt, lite_sdk_results.txt, no_layer_results.txt"
