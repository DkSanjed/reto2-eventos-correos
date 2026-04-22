variable "aws_region" {
  type        = string
  description = "Región AWS"
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Prefijo para nombrar recursos"
  default     = "reto2-fleet-alerts"
}

variable "environment" {
  type        = string
  description = "Ambiente"
  default     = "prod"
}

variable "alert_email_to" {
  type        = string
  description = "Gmail destinatario de alertas de emergencia"
}

variable "alert_email_from" {
  type        = string
  description = "Email remitente (debe estar verificado en SES — en sandbox, usar el mismo que alert_email_to)"
}

variable "api_throttling_rate_limit" {
  type        = number
  description = "Rate limit API Gateway (req/s) — requisito del reto: 15"
  default     = 15
}

variable "api_throttling_burst_limit" {
  type        = number
  description = "Burst limit API Gateway — requisito del reto: default (2000)"
  default     = 2000
}

variable "lambda_reserved_concurrency" {
  type        = number
  description = "Concurrencia reservada Lambda — requisito del reto: máximo 10"
  default     = 10
}

variable "lambda_timeout_seconds" {
  type        = number
  default     = 10
}

variable "lambda_memory_mb" {
  type        = number
  default     = 256
}

variable "sqs_batch_size" {
  type        = number
  description = "Tamaño batch del event source mapping (1-10)"
  default     = 10
}

variable "log_retention_days" {
  type        = number
  default     = 7
}
