terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ─── ZIP del código Lambda ────────────────────────────────────────────────────

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# ─── IAM Role para Lambda ─────────────────────────────────────────────────────

resource "aws_iam_role" "lambda_role" {
  name = "reto2-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "ses_policy" {
  name = "reto2-ses-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ses:SendEmail", "ses:SendRawEmail"]
      Resource = "*"
    }]
  })
}

# ─── Lambda ──────────────────────────────────────────────────────────────────

resource "aws_lambda_function" "vehicle_events" {
  function_name    = "reto2-vehicle-events"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      ALERT_EMAIL = var.alert_email
    }
  }
}

# ─── SES: verificar email ─────────────────────────────────────────────────────

resource "aws_sesv2_email_identity" "alert_email" {
  email_identity = var.alert_email
}

# ─── API Gateway ──────────────────────────────────────────────────────────────

resource "aws_api_gateway_rest_api" "fleet_api" {
  name = "reto2-fleet-api"
}

resource "aws_api_gateway_resource" "events" {
  rest_api_id = aws_api_gateway_rest_api.fleet_api.id
  parent_id   = aws_api_gateway_rest_api.fleet_api.root_resource_id
  path_part   = "events"
}

resource "aws_api_gateway_method" "post_events" {
  rest_api_id      = aws_api_gateway_rest_api.fleet_api.id
  resource_id      = aws_api_gateway_resource.events.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.fleet_api.id
  resource_id             = aws_api_gateway_resource.events.id
  http_method             = aws_api_gateway_method.post_events.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.vehicle_events.invoke_arn
}

resource "aws_api_gateway_deployment" "prod" {
  rest_api_id = aws_api_gateway_rest_api.fleet_api.id

  depends_on = [aws_api_gateway_integration.lambda_integration]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.fleet_api.id
  deployment_id = aws_api_gateway_deployment.prod.id
  stage_name    = "prod"
}

resource "aws_api_gateway_method_settings" "throttle" {
  rest_api_id = aws_api_gateway_rest_api.fleet_api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"

  settings {
    throttling_rate_limit  = 15
    throttling_burst_limit = 2000
  }
}

resource "aws_api_gateway_usage_plan" "throttle" {
  name = "reto2-throttle"

  api_stages {
    api_id = aws_api_gateway_rest_api.fleet_api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  throttle_settings {
    rate_limit  = 15
    burst_limit = 2000
  }
}

resource "aws_api_gateway_api_key" "fleet_key" {
  name = "reto2-fleet-key"
}

resource "aws_api_gateway_usage_plan_key" "fleet_key" {
  key_id        = aws_api_gateway_api_key.fleet_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.throttle.id
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.vehicle_events.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.fleet_api.execution_arn}/*/*"
}