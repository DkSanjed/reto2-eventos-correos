# =========================================
# IAM — Roles con principio de mínimo privilegio
# =========================================

# -----------------------------------------
# Rol 1: API Gateway -> SQS SendMessage
# -----------------------------------------
data "aws_iam_policy_document" "apigw_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigw_to_sqs" {
  name               = "${var.project_name}-apigw-to-sqs"
  assume_role_policy = data.aws_iam_policy_document.apigw_assume.json
}

data "aws_iam_policy_document" "apigw_sqs_send" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.events.arn]
  }
}

resource "aws_iam_role_policy" "apigw_sqs_send" {
  name   = "sqs-send-message"
  role   = aws_iam_role.apigw_to_sqs.id
  policy = data.aws_iam_policy_document.apigw_sqs_send.json
}

# -----------------------------------------
# Rol 2: Lambda execution role
# -----------------------------------------
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project_name}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# SQS read (para que event source mapping funcione)
data "aws_iam_policy_document" "lambda_sqs" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [aws_sqs_queue.events.arn]
  }
}

resource "aws_iam_role_policy" "lambda_sqs" {
  name   = "sqs-consume"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_sqs.json
}

# SES send (restringido al identity verificado)
data "aws_iam_policy_document" "lambda_ses" {
  statement {
    effect  = "Allow"
    actions = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = [
      "arn:aws:ses:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:identity/${var.alert_email_from}",
    ]
  }
}

resource "aws_iam_role_policy" "lambda_ses" {
  name   = "ses-send-email"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_ses.json
}
