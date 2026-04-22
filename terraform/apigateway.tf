# =========================================
# API Gateway REST — integración directa a SQS
# =========================================
# POST /events -> AWS service integration (SQS SendMessage)
# Sin Lambda proxy de ingesta: menos latencia, menos costo, responde 200 inmediato.
#
# Stage throttling:
#   rate  = 15 req/s   (requisito duro del reto)
#   burst = 2000       (default — permite absorber los 1000 iniciales de k6)

resource "aws_api_gateway_rest_api" "this" {
  name        = var.project_name
  description = "Reto 2 — ingesta de eventos de flota vehicular"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "events" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "events"
}

resource "aws_api_gateway_method" "post_events" {
  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.events.id
  http_method      = "POST"
  authorization    = "NONE"
  # Seguridad v2: requerir header x-api-key. Sin key => 403 Forbidden.
  api_key_required = true
}

# Integración AWS service -> SQS SendMessage
resource "aws_api_gateway_integration" "sqs" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.events.id
  http_method             = aws_api_gateway_method.post_events.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  credentials             = aws_iam_role.apigw_to_sqs.arn

  # URI format: arn:aws:apigateway:<region>:sqs:path/<accountId>/<queueName>
  uri = "arn:aws:apigateway:${data.aws_region.current.name}:sqs:path/${data.aws_caller_identity.current.account_id}/${aws_sqs_queue.events.name}"

  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  # VTL template: convierte el body JSON en form-encoded SendMessage call
  request_templates = {
    "application/json" = "Action=SendMessage&MessageBody=$util.urlEncode($input.body)"
  }

  passthrough_behavior = "NEVER"
}

# Respuesta 200 al cliente (k6 recibe 200 apenas SQS acepta)
resource "aws_api_gateway_method_response" "ok" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.post_events.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "ok" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.events.id
  http_method = aws_api_gateway_method.post_events.http_method
  status_code = aws_api_gateway_method_response.ok.status_code

  response_templates = {
    "application/json" = "{\"status\":\"queued\"}"
  }

  depends_on = [aws_api_gateway_integration.sqs]
}

# ==========
# Deployment + Stage
# ==========
resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    # Fuerza redeploy cuando cambian los recursos
    redeploy = sha1(jsonencode([
      aws_api_gateway_resource.events.id,
      aws_api_gateway_method.post_events.id,
      aws_api_gateway_integration.sqs.id,
      aws_api_gateway_integration_response.ok.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.sqs,
    aws_api_gateway_integration_response.ok,
  ]
}

resource "aws_api_gateway_stage" "prod" {
  stage_name    = var.environment
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw.arn
    format = jsonencode({
      requestId       = "$context.requestId"
      ip              = "$context.identity.sourceIp"
      requestTime     = "$context.requestTime"
      httpMethod      = "$context.httpMethod"
      resourcePath    = "$context.resourcePath"
      status          = "$context.status"
      responseLength  = "$context.responseLength"
      integrationLatency = "$context.integrationLatency"
    })
  }

  depends_on = [aws_api_gateway_account.this]
}

# Method settings — logging/metrics.
# NOTA: el throttling rate=15 / burst=2000 se movió al usage plan (ver apikey.tf),
# que lo aplica POR API KEY. Así cada cliente tiene su cupo independiente y el
# throttling de stage queda abierto como fallback general.
resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled    = true
    logging_level      = "INFO"
    data_trace_enabled = false
  }
}

# ==========
# API Gateway -> CloudWatch Logs role (a nivel cuenta, requerido por AWS)
# ==========
data "aws_iam_policy_document" "apigw_cw_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigw_cloudwatch" {
  name               = "${var.project_name}-apigw-cw-logs"
  assume_role_policy = data.aws_iam_policy_document.apigw_cw_assume.json
}

resource "aws_iam_role_policy_attachment" "apigw_cloudwatch" {
  role       = aws_iam_role.apigw_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "this" {
  cloudwatch_role_arn = aws_iam_role.apigw_cloudwatch.arn
}
