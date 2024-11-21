[
  {
    "name": "app",
    "image": "${app_image}",
    "cpu": 0,
    "portMappings": [
      {
        "name": "app-8000-tcp",
        "containerPort": 8000,
        "hostPort": 8000,
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
        "name": "OTEL_LOG_LEVEL",
        "value": "debug"
      },
      {
        "name": "OTEL_TRACES_SAMPLER",
        "value": "xray"
      },
      {
        "name": "OTEL_TRACES_SAMPLER_ARG",
        "value": "endpoint=http://localhost:2000"
      },
      {
        "name": "OTEL_LOGS_EXPORTER",
        "value": "none"
      },
      {
        "name": "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT",
        "value": "http://localhost:4316/v1/traces"
      },
      {
        "name": "OTEL_AWS_APPLICATION_SIGNALS_EXPORTER_ENDPOINT",
        "value": "http://localhost:4316/v1/metrics"
      },
      {
        "name": "OTEL_AWS_APPLICATION_SIGNALS_ENABLED",
        "value": "true"
      },
      {
        "name": "OTEL_RESOURCE_ATTRIBUTES",
        "value": "service.name=${app_service_name}, aws.log.group.names=/ecs/node-e2e-test"
      },
      {
        "name": "OTEL_METRICS_EXPORTER",
        "value": "none"
      },
      {
        "name": "NODE_OPTIONS",
        "value": "--require /otel-auto-instrumentation-node/autoinstrumentation.js"
      }
    ],
    "mountPoints": [
      {
        "sourceVolume": "opentelemetry-auto-instrumentation",
        "containerPath": "/otel-auto-instrumentation-node",
        "readOnly": false
      }
    ],
    "dependsOn": [
      {
        "containerName": "init",
        "condition": "SUCCESS"
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/node-e2e-test",
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
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/node-ecs-cwagent",
        "awslogs-create-group": "true",
        "awslogs-region": "${aws_region}",
        "awslogs-stream-prefix": "ecs"
      }
    },
    "command": [
      "cp",
      "-a",
      "/autoinstrumentation/.",
      "/otel-auto-instrumentation-node"
    ],
    "mountPoints": [
      {
        "sourceVolume": "opentelemetry-auto-instrumentation",
        "containerPath": "/otel-auto-instrumentation-node",
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
        "awslogs-group": "/ecs/node-ecs-cwagent",
        "awslogs-create-group": "true",
        "awslogs-region": "${aws_region}",
        "awslogs-stream-prefix": "ecs"
      }
    }
  },
  {
    "name": "traffic-gen",
    "image": "amazonlinux:2",
    "cpu": 0,
    "essential": true,
    "command": [
      "sh",
      "-c",
      "while true; do curl http://localhost:8000/client-call; sleep 10; done"
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/node-ecs-traffic-gen",
        "awslogs-create-group": "true",
        "awslogs-region": "${aws_region}",
        "awslogs-stream-prefix": "ecs"
      }
    }
  }
]