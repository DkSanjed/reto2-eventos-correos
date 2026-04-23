provider "aws" {
  region = "us-east-1"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "aws_s3_bucket" "portal_resultados" {
  bucket = "portal-k6-luis-padilla-${random_string.suffix.result}"
}

resource "aws_s3_bucket_website_configuration" "portal_config" {
  bucket = aws_s3_bucket.portal_resultados.id
  index_document { suffix = "index.html" }
}

resource "aws_s3_bucket_public_access_block" "portal_access" {
  bucket                  = aws_s3_bucket.portal_resultados.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "allow_public_access" {
  bucket = aws_s3_bucket.portal_resultados.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.portal_resultados.arn}/*"
    }]
  })
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "role_lambda_emergencias_luis"
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
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "procesador_eventos" {
  filename         = "../src/lambda_function.zip"
  source_code_hash = filebase64sha256("../src/lambda_function.zip")
  function_name    = "procesador-emergencias-luis"
  role             = aws_iam_role.iam_for_lambda.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  timeout          = 30
  reserved_concurrent_executions = -1

  environment {
    variables = {
      GMAIL_USER         = var.gmail_user
      GMAIL_APP_PASSWORD = var.gmail_app_password
    }
  }
}

resource "aws_apigatewayv2_api" "api_vehicular" {
  name          = "api-eventos-vehiculares-luis"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api_vehicular.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = 15
    throttling_burst_limit = 1000
  }
}

resource "aws_apigatewayv2_integration" "lambda_int" {
  api_id                 = aws_apigatewayv2_api.api_vehicular.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.procesador_eventos.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_eventos" {
  api_id    = aws_apigatewayv2_api.api_vehicular.id
  route_key = "POST /eventos"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_int.id}"
}

resource "aws_lambda_permission" "api_gw" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.procesador_eventos.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api_vehicular.execution_arn}/*/*"
}

output "url_para_k6" {
  value = "${aws_apigatewayv2_api.api_vehicular.api_endpoint}/eventos"
}

output "url_del_portal_s3" {
  value = aws_s3_bucket_website_configuration.portal_config.website_endpoint
}