# =========================================
# Lambda — Processor (SQS -> SES)
# =========================================

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/handler.py"
  output_path = "${path.module}/build/handler.zip"
}

resource "aws_lambda_function" "processor" {
  function_name = "${var.project_name}-processor"
  role          = aws_iam_role.lambda_exec.arn
  runtime       = "python3.12"
  handler       = "handler.lambda_handler"

  # Optimización v2: ARM64 Graviton2 — ~20% más rápido y ~20% más barato que x86_64.
  architectures = ["arm64"]

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout     = var.lambda_timeout_seconds
  memory_size = var.lambda_memory_mb

  # Optimización v2: publicar versión para habilitar SnapStart.
  publish = true

  # Optimización v2: SnapStart — reduce cold start de ~580ms a ~80ms.
  # Gratis para runtimes Python. Solo aplica a versiones publicadas, no a $LATEST.
  snap_start {
    apply_on = "PublishedVersions"
  }

  # NOTA: el tope de 10 instancias simultáneas se aplica en el event source mapping
  # (scaling_config.maximum_concurrency). No usamos reserved_concurrent_executions
  # porque en cuentas nuevas de AWS la cuota total es 10, y reservar 10 aquí
  # dejaría 0 para cualquier otra Lambda (AWS lo rechaza).
  # Como Lambda SOLO se invoca desde SQS, el cap del event source mapping es efectivo.

  environment {
    variables = {
      ALERT_EMAIL_TO   = var.alert_email_to
      ALERT_EMAIL_FROM = var.alert_email_from
      LOG_LEVEL        = "INFO"
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.lambda.name
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_cloudwatch_log_group.lambda,
  ]
}

# =========================================
# Alias "live" — apunta a la última versión publicada
# =========================================
# Requerido para SnapStart: el ESM debe invocar una versión o alias, no $LATEST.
# El alias permite re-apuntar a nuevas versiones sin tocar el ESM.

resource "aws_lambda_alias" "live" {
  name             = "live"
  description      = "Alias estable apuntando a la última versión publicada"
  function_name    = aws_lambda_function.processor.function_name
  function_version = aws_lambda_function.processor.version
}

# =========================================
# Event Source Mapping — SQS -> Lambda (alias "live")
# =========================================
# batch_size=10 + window=0  -> latencia mínima, máximo throughput
# ReportBatchItemFailures   -> si 1 msg falla, solo ése vuelve a la cola
# maximum_concurrency=10    -> refuerza el tope de 10 instancias
# function_name = alias ARN -> habilita SnapStart (vs $LATEST sin SnapStart)

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn                   = aws_sqs_queue.events.arn
  function_name                      = aws_lambda_alias.live.arn
  batch_size                         = var.sqs_batch_size
  maximum_batching_window_in_seconds = 0
  function_response_types            = ["ReportBatchItemFailures"]
  enabled                            = true

  scaling_config {
    maximum_concurrency = var.lambda_reserved_concurrency
  }
}
