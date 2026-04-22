# =========================================
# SES — Email identity verification
# =========================================
# En sandbox (default), SES solo envía desde/hacia identities verificados.
# Terraform dispara el email de verificación; el usuario debe hacer click en el link
# ANTES del primer envío.
#
# Como From y To son el mismo Gmail, basta con verificar 1 identity.

resource "aws_ses_email_identity" "sender" {
  email = var.alert_email_from
}

# Si alert_email_to != alert_email_from, verificamos ambos
resource "aws_ses_email_identity" "recipient" {
  count = var.alert_email_from == var.alert_email_to ? 0 : 1
  email = var.alert_email_to
}
