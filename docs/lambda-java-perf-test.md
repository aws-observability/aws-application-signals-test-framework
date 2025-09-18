# How to Run Lambda Java Performance Test
The [java-lambda-layer-performance-test](https://github.com/aws-observability/aws-application-signals-test-framework/actions/workflows/java-lambda-layer-perf-test.yml) workflow will check out a branch from the [ADOT Java Agent repo](https://github.com/aws-observability/aws-otel-java-instrumentation) and build a Lambda Java Layer from that branch. Then it will run performance tests with the generated Lambda Java Layer and build the report.

For example, to test a Lambda Layer built from branch "release/v2.11.x":
1. Open the [java-lambda-layer-performance-test](https://github.com/aws-observability/aws-application-signals-test-framework/actions/workflows/java-lambda-layer-perf-test.yml) workflow and click "Run workflow".
2. Use workflow from "Branch: main". Enter "release/v2.11.x" in "ADOT Java branch to use" and click "Run workflow".
3. After the workflow run finishes, the performance testing report can be found in the generated artifacts under "java-performance-test-results".