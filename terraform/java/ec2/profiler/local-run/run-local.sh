#!/bin/bash
# Runs the Java EC2 profiler e2e checks locally: the three profiled sample-app variants and the OTel
# Collector run in one Docker container (see container-setup.sh) instead of on EC2, export real
# profiles to CloudWatch Profiles, and the same validator checks as java-ec2-profiler-test.yml run
# against them. Nothing is created in AWS; only profile data is written under a unique service name.
#
# Usage:
#   run-local.sh --profile <aws-profile> (--agent-jar <jar> | --java-repo <aws-otel-java-instrumentation>)
#                [--region us-east-1] [--java-version 17] [--profiles-role-arn <arn>]
#                [--checks wall-profile,identity,...] [--keep]
#
# The AWS profile's account must be enabled for CloudWatch Profiles (or pass --profiles-role-arn for
# one that is). Its credentials are only exported into the environment of this script, the
# container's collector and the validator; they are not written to disk.
set -o errexit -o nounset -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
PROFILER_TF_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

AWS_PROFILE_NAME=""
AGENT_JAR=""
JAVA_REPO=""
REGION="us-east-1"
JAVA_VERSION="17"
PROFILES_ROLE_ARN=""
CHECKS=""
KEEP=false

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-1}"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --profile) AWS_PROFILE_NAME="$2"; shift 2 ;;
    --agent-jar) AGENT_JAR="$2"; shift 2 ;;
    --java-repo) JAVA_REPO="$2"; shift 2 ;;
    --region) REGION="$2"; shift 2 ;;
    --java-version) JAVA_VERSION="$2"; shift 2 ;;
    --profiles-role-arn) PROFILES_ROLE_ARN="$2"; shift 2 ;;
    --checks) CHECKS="$2"; shift 2 ;;
    --keep) KEEP=true; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done
[ -n "$AWS_PROFILE_NAME" ] || { echo "--profile is required"; usage; }
[ -n "$AGENT_JAR" ] || [ -n "$JAVA_REPO" ] || { echo "--agent-jar or --java-repo is required"; usage; }
for tool in docker aws python3; do
  command -v "$tool" > /dev/null || { echo "$tool is required"; exit 1; }
done

# The validator and the sample app build with JDK 17 (Gradle 8.10 cannot run on newer JDKs).
if [ -x /usr/libexec/java_home ] && /usr/libexec/java_home -v 17 > /dev/null 2>&1; then
  JAVA_HOME="$(/usr/libexec/java_home -v 17)"
  export JAVA_HOME
fi

load_credentials() {
  eval "$(aws configure export-credentials --profile "$AWS_PROFILE_NAME" --format env)"
  export AWS_REGION="$REGION"
}
load_credentials
echo "AWS identity: $(aws sts get-caller-identity --query Arn --output text)"

TESTING_ID="local-$(date +%m%d%H%M)-$RANDOM"
SERVICE_NAME="java-sample-application-$TESTING_ID"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/profiler-local-$TESTING_ID.XXXX")"
CONTAINER="profiler-local-$TESTING_ID"
mkdir -p "$WORK_DIR/logs"
echo "Test id: $TESTING_ID   work dir: $WORK_DIR"

cleanup() {
  if [ "$KEEP" = true ]; then
    echo "Container $CONTAINER left running (--keep). Remove it with: docker rm -f $CONTAINER"
  else
    docker rm -f "$CONTAINER" > /dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# ---- Build inputs ----
echo "Building the sample app..."
(cd "$REPO_ROOT" && ./gradlew -q -p sample-apps/java :springboot-main-service:build \
  -PjavaVersion="$JAVA_VERSION" -x test) > "$WORK_DIR/logs/sample-app-build.log" 2>&1 \
  || { echo "Sample app build failed; see $WORK_DIR/logs/sample-app-build.log"; exit 1; }
cp "$REPO_ROOT"/sample-apps/java/springboot-main-service/build/libs/springboot-main-service-*-SNAPSHOT.jar \
  "$WORK_DIR/main-service.jar"

if [ -z "$AGENT_JAR" ]; then
  echo "Building the ADOT Java agent from $JAVA_REPO..."
  (cd "$JAVA_REPO" && ./gradlew -q :otelagent:assemble -x javadoc) > "$WORK_DIR/logs/agent-build.log" 2>&1 \
    || { echo "Agent build failed; see $WORK_DIR/logs/agent-build.log"; exit 1; }
  for jar in "$JAVA_REPO"/otelagent/build/libs/aws-opentelemetry-agent-*.jar; do
    case "$jar" in *-sources.jar|*-javadoc.jar) ;; *) AGENT_JAR="$jar" ;; esac
  done
fi
[ -f "$AGENT_JAR" ] || { echo "Agent jar not found: $AGENT_JAR"; exit 1; }
cp "$AGENT_JAR" "$WORK_DIR/adot.jar"
echo "Agent: $AGENT_JAR"

# Render the collector config the way Terraform's templatefile() does.
python3 - "$PROFILER_TF_DIR/otel-collector-config.yaml" "$WORK_DIR/otel-collector-config.yaml" \
  "$REGION" "$PROFILES_ROLE_ARN" <<'EOF'
import sys
src, dst, region, role = sys.argv[1:5]
out, keep = [], True
for line in open(src):
    s = line.strip()
    if s.startswith("%{ if"):
        keep = bool(role)
        continue
    if s.startswith("%{ endif"):
        keep = True
        continue
    if keep:
        out.append(line.replace("${region}", region).replace("${profiles_role_arn}", role))
open(dst, "w").writelines(out)
EOF
cp "$SCRIPT_DIR/container-setup.sh" "$WORK_DIR/"
COLLECTOR_VERSION="$(grep -A1 'variable "otel_collector_version"' "$PROFILER_TF_DIR/variables.tf" \
  | grep -o '"[0-9.]*"' | tr -d '"')"

# grep without -q reads all input, so the pipe can't fail with SIGPIPE under pipefail.
logs_have() { docker logs "$CONTAINER" 2>&1 | grep "$1" > /dev/null; }

# ---- Start the apps ----
echo "Starting the container (sample apps + collector)..."
docker run -d --name "$CONTAINER" --memory 4g \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION \
  -e SERVICE_NAME="$SERVICE_NAME" -e OTEL_COLLECTOR_VERSION="$COLLECTOR_VERSION" \
  -v "$WORK_DIR:/work" "public.ecr.aws/amazoncorretto/amazoncorretto:${JAVA_VERSION}-al2023" \
  /work/container-setup.sh > /dev/null
for _ in $(seq 1 60); do
  if logs_have TRAFFIC_STARTED; then break; fi
  if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" != "true" ]; then
    echo "Container setup failed:"; docker logs "$CONTAINER" 2>&1 | tail -n 40; exit 1
  fi
  sleep 10
done
logs_have TRAFFIC_STARTED \
  || { echo "Apps did not come up in 10 minutes:"; docker logs "$CONTAINER" 2>&1 | tail -n 40; exit 1; }
docker logs "$CONTAINER" 2>&1 | grep "App on port"
echo "Deploy-time context: $(cat "$WORK_DIR/profiler-context.json")"

# ---- Run the checks (same list and services as java-ec2-profiler-test.yml) ----
ALL_CHECKS="wall-profile: operation-label: thread-state-label: app-stack-frames: operation-attribution:
alloc-space-profile: alloc-objects-profile: rotation-windows: identity: cpu-profile:-cpu
cpu-operation-label:-cpu cpu-no-thread-state:-cpu cpu-identity:-cpu
unsampled-operation-label:-unsampled unsampled-identity:-unsampled"
echo "Running checks (each retries for up to ~10 minutes while profiles are ingested)..."
failed=0
results=""
cd "$REPO_ROOT"
for entry in $ALL_CHECKS; do
  check="${entry%%:*}"
  suffix="${entry#*:}"
  if [ -n "$CHECKS" ] && [[ ",$CHECKS," != *",$check,"* ]]; then continue; fi
  load_credentials
  if ./gradlew -q validator:run --args="-c java/ec2/profiler/$check-validation.yml \
      --testing-id $TESTING_ID --endpoint http://localhost:8080 --region $REGION \
      --service-name $SERVICE_NAME$suffix --instance-ami local --instance-id local \
      --profiles-role-arn '$PROFILES_ROLE_ARN' \
      --profile-context-file $WORK_DIR/profiler-context.json --rollup" \
      > "$WORK_DIR/logs/$check.log" 2>&1; then
    line="PASS  $check ($SERVICE_NAME$suffix)"
  else
    line="FAIL  $check ($SERVICE_NAME$suffix)  log: $WORK_DIR/logs/$check.log"
    failed=$((failed + 1))
  fi
  echo "$line"
  results+="$line"$'\n'
done

echo
echo "==== Summary ($TESTING_ID) ===="
printf '%s' "$results"
echo "Logs: $WORK_DIR/logs"
[ "$failed" -eq 0 ]
