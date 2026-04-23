variable "gmail_user" {
  description = "Cuenta Gmail para envío de alertas de emergencia"
  type        = string
  sensitive   = true
}

variable "gmail_app_password" {
  description = "App Password de Gmail (generada en configuración de cuenta Google)"
  type        = string
  sensitive   = true
}