# =========================================
# API Key + Usage Plan  (seguridad v2)
# =========================================
# - La API key se requiere por header "x-api-key" (ver api_key_required en apigateway.tf).
# - El usage plan aplica el throttling del reto (rate=15/s, burst=2000) POR KEY.
# - Múltiples keys podrían asociarse al mismo plan en el futuro sin cambios.

resource "aws_api_gateway_api_key" "k6" {
  name        = "${var.project_name}-k6"
  description = "Key para pruebas k6 del reto (cliente único)"
  enabled     = true
}

resource "aws_api_gateway_usage_plan" "prod" {
  name        = "${var.project_name}-prod-plan"
  description = "Usage plan con rate=15/s, burst=2000 por key (requisito del reto)"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  throttle_settings {
    rate_limit  = var.api_throttling_rate_limit  # 15 req/s
    burst_limit = var.api_throttling_burst_limit # 2000
  }
}

resource "aws_api_gateway_usage_plan_key" "k6" {
  key_id        = aws_api_gateway_api_key.k6.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.prod.id
}
