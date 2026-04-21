variable "aws_region" {
  default = "us-east-1"
}

variable "alert_email" {
  description = "Gmail verificado en SES para recibir alertas"
  type        = string
}

variable "lambda_timeout" {
  default = 30
}

variable "lambda_memory" {
  default = 128
}