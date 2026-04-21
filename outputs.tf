output "endpoint_url" {
  description = "URL del endpoint para k6"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/events"
}

output "lambda_name" {
  value = aws_lambda_function.vehicle_events.function_name
}