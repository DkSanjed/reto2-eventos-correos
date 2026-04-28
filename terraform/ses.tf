resource "aws_ses_email_identity" "sender" {
  email = var.alert_email_from
}

resource "aws_ses_email_identity" "recipient" {
  count = var.alert_email_from == var.alert_email_to ? 0 : 1
  email = var.alert_email_to
}
