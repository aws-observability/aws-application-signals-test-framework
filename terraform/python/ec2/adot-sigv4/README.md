# Python OTLP SigV4 forwarding proxy E2E

The `python-sigv4-proxy-validation.yml` workflow builds a chosen Python ADOT ref
and runs the existing SigV4 test with compression unset and with gzip. To test
Python instrumentation PR #928, dispatch it with `adot-ref=refs/pull/928/head`.
SDK CI callers can enable the same coverage on the existing
`python-ec2-adot-sigv4-test.yml` workflow with `use-otlp-proxy: true`.

With `use_otlp_proxy=true`, both sample services select `otlp/sigv4` for all three
signals and use these endpoints:

```sh
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://127.0.0.1:4318/v1/traces
OTEL_EXPORTER_OTLP_LOGS_ENDPOINT=http://127.0.0.1:4318/v1/logs
OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=http://127.0.0.1:4318/v1/metrics
```

The proxy routes each connection by its first OTLP request path and forwards the
original HTTP byte stream to the corresponding regional AWS endpoint over TLS.
It preserves the original `Host`, authorization and other headers, request path,
and compressed payload. It does not decode protobuf or sign requests. Each
exporter's persistent connection stays with its signal's destination.

The existing validators check traces, custom OTLP logs, and custom OTLP metrics
through CloudWatch PromQL. AWS receives and verifies the signatures created by
ADOT. Both sample services resolve credentials through the EC2 role, with
`AWS_REGION` set because the local proxy URL does not identify an AWS region.
