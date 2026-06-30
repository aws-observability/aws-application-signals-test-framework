output "api-gateway-url" {
  value = module.api-gateway.api_gateway_url
}

output "function_role_name" {
  value = module.hello-lambda-function.lambda_function_name
}

output "sdk_layer_arn" {
  value = aws_lambda_layer_version.sdk_layer[0].arn
}
