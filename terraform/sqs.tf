# =========================================
# SQS — Cola principal + Dead Letter Queue
# =========================================
# Decisión de arquitectura:
#   - Queue Standard (throughput ilimitado, vs 300 msg/s en FIFO)
#   - DLQ con maxReceiveCount=3 -> cero pérdida garantizada
#   - visibility_timeout = 6 × lambda timeout (recomendación AWS)

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project_name}-dlq"
  message_retention_seconds = 1209600 # 14 días
  sqs_managed_sse_enabled   = true
}

resource "aws_sqs_queue" "events" {
  name                       = "${var.project_name}-events"
  visibility_timeout_seconds = var.lambda_timeout_seconds * 6 # 60s
  message_retention_seconds  = 345600                         # 4 días
  receive_wait_time_seconds  = 0                              # long polling lo maneja el event source mapping
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

# Alarma CloudWatch: DLQ con mensajes = algo falló
resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${var.project_name}-dlq-not-empty"
  alarm_description   = "Mensajes en la DLQ — indica fallos de procesamiento"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }
}
