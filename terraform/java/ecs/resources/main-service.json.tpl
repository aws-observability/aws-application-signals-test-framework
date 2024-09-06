[
  {
    "name": "app",
    "image": "${app_image}",
    "cpu": 0,
    "portMappings": [
      {
        "name": "app-8080-tcp",
        "containerPort": 8080,
        "hostPort": 8080,
        "protocol": "tcp",
        "appProtocol": "http"
      }
    ],
    "essential": true,
    "environment": [
      {
        "name": "OTEL_EXPORTER_OTLP_PROTOCOL",
        "value": "http/protobuf"
      },
      {
        "name": "OTEL_AWS_APPLICATION_SIGNALS_ENABLED",
        "value": "true"
      },
      {
        "name": "OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT",
        "value": "http://localhost:4316/v1/metrics"
      },
      {
        "name": "OTEL_RESOURCE_ATTRIBUTES",
        "value": "service.name=${app_service_name}"
      },
      {
        "name": "OTEL_METRICS_EXPORTER",
        "value": "none"
      },
      {
        "name": "JAVA_TOOL_OPTIONS",
        "value": "-javaagent:/otel-auto-instrumentation/javaagent.jar"
      },
      {
        "name": "OTEL_LOGS_EXPORTER",
        "value": "none"
      },
      {
        "name": "OTEL_TRACES_SAMPLER",
        "value": "xray"
      },
      {
        "name": "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT",
        "value": "http://localhost:4316/v1/traces"
      },
      {
        "name": "OTEL_PROPAGATORS",
        "value": "tracecontext,baggage,b3,xray"
      }
    ],
    "mountPoints": [
      {
        "sourceVolume": "opentelemetry-auto-instrumentation",
        "containerPath": "/otel-auto-instrumentation",
        "readOnly": false
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/service-e2e-test",
        "awslogs-create-group": "true",
        "awslogs-region": "${aws_region}",
        "awslogs-stream-prefix": "ecs"
      }
    }
  },
  {
    "name": "init",
    "image": "${init_image}",
    "cpu": 0,
    "essential": false,
    "command": [
      "cp",
      "/javaagent.jar",
      "/otel-auto-instrumentation/javaagent.jar"
    ],
    "mountPoints": [
      {
        "sourceVolume": "opentelemetry-auto-instrumentation",
        "containerPath": "/otel-auto-instrumentation",
        "readOnly": false
      }
    ]
  },
  {
    "name": "ecs-cwagent",
    "image": "${cwagent_image}",
    "cpu": 0,
    "essential": true,
    "environment": [
      {
        "name": "CW_CONFIG_CONTENT",
        "value": "{\"agent\": {\"debug\": true}, \"traces\": {\"traces_collected\": {\"application_signals\": {\"enabled\": true}}}, \"logs\": {\"metrics_collected\": {\"application_signals\": {\"enabled\": true}}}}"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/ecs-cwagent",
        "awslogs-create-group": "true",
        "awslogs-region": "${aws_region}",
        "awslogs-stream-prefix": "ecs"
      }
    }
  },
  {
    "name": "traffic-gen",
    "image": "curlimages/curl:8.8.0",
    "cpu": 0,
    "essential": true,
    "command": [
      "sh",
      "-c",
      "while true; do curl http://localhost:8080/; sleep 15; done"
    ]
  }
]