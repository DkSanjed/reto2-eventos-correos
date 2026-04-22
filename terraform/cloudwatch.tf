# =========================================
# CloudWatch Log Groups
# =========================================
# Se crean explícitamente con retention para evitar logs huérfanos sin límite.

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}-processor"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "apigw" {
  name              = "/aws/apigateway/${var.project_name}"
  retention_in_days = var.log_retention_days
}
