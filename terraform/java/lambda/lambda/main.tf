locals {
  architecture = var.architecture == "x86_64" ? "x64" : "arm64"
}

resource "aws_lambda_layer_version" "sdk_layer" {
  count               = var.is_canary ? 0 : 1
  layer_name          = var.sdk_layer_name
  filename            = "${var.layer_artifacts_directory}/layer.zip"
  compatible_runtimes = ["java17", "java21"]
  license_info        = "Apache-2.0"
  source_code_hash    = filebase64sha256("${var.layer_artifacts_directory}/layer.zip")
}

module "hello-lambda-function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = ">= 2.24.0"

  architectures = compact([var.architecture])
  function_name = var.function_name
  handler       = "com.amazon.sampleapp.LambdaHandler::handleRequest"
  runtime       = var.runtime

  create_package         = false
  local_existing_package = "${var.layer_artifacts_directory}/java-function.zip"

  memory_size = 512
  timeout     = 30

  layers = var.is_canary ? [local.sdk_layer_arns[var.region]] : [aws_lambda_layer_version.sdk_layer[0].arn]

  environment_variables = {
    AWS_LAMBDA_EXEC_WRAPPER     = "/opt/otel-instrument"
    OTEL_SERVICE_NAME           = var.function_name
  }

  tracing_mode = var.tracing_mode

  attach_policy_statements = true
  policy_statements = {
    s3 = {
      effect = "Allow"
      actions = [
        "s3:ListAllMyBuckets",
        "s3:ListBucket"
      ]
      resources = [
        "*"
      ]
    }
  }
}

module "api-gateway" {
  source = "../api-gateway-proxy"

  name                = var.function_name
  function_name       = module.hello-lambda-function.lambda_function_name
  function_invoke_arn = module.hello-lambda-function.lambda_function_invoke_arn
  enable_xray_tracing = var.tracing_mode == "Active"
}

resource "aws_iam_role_policy_attachment" "hello-lambda-cloudwatch" {
  role       = module.hello-lambda-function.lambda_function_name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "test_xray" {
  role       = module.hello-lambda-function.lambda_function_name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}