# CLOUDWATCH AGENT CONFIG.
This cloudwatch-agent.json file is a version of the amazon-cloudwatch-agent fitted to the needs of the python sample app using custom metrics. Shown in public docs: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AppSignals-CustomMetrics.html#AppSignals-CustomMetrics-OpenTelemetry

It handles the custom metrics through the addition of the otlp ports:
      "otlp": {
        "grpc_endpoint": "0.0.0.0:4317",
        "http_endpoint": "0.0.0.0:4318"
      }