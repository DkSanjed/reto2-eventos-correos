# 1. Configuración del Proveedor y Región
provider "aws" {
  region = "us-east-1" # Región donde tienes tus créditos de $100
}

# 2. Rol de IAM para que la Lambda tenga permisos de ejecución y logs
resource "aws_iam_role" "iam_for_lambda" {
  name = "role_lambda_emergencias_luis"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Permiso para escribir logs en CloudWatch (Requerimiento de Logs del Reto)
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 3. Función Lambda (El Procesador)
resource "aws_lambda_function" "procesador_eventos" {
  filename      = "../src/lambda_function.zip" # Ruta al archivo que comprimiste
  function_name = "procesador-emergencias-luis"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"

  # RESTRICCIÓN TÉCNICA: Máximo 10 instancias activas (Concurrencia Reservada)
 # reserved_concurrent_executions = 5 
}

# 4. API Gateway (El Receptor de los 1000 eventos)
resource "aws_apigatewayv2_api" "api_vehicular" {
  name          = "api-vehicular-luis"
  protocol_type = "HTTP"
}

# Configuración de Throttling (Límite de velocidad)
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api_vehicular.id
  name        = "$default"
  auto_deploy = true

  # RESTRICCIÓN TÉCNICA: Tasa máxima de 15 peticiones por segundo
  default_route_settings {
    throttling_burst_limit = 10
    throttling_rate_limit  = 15
  }
}

# 5. Integración entre API y Lambda
resource "aws_apigatewayv2_integration" "lambda_int" {
  api_id           = aws_apigatewayv2_api.api_vehicular.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.procesador_eventos.invoke_arn
}

# Ruta para recibir los POST en /eventos
resource "aws_apigatewayv2_route" "post_route" {
  api_id    = aws_apigatewayv2_api.api_vehicular.id
  route_key = "POST /eventos"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_int.id}"
}

# Permiso para que API Gateway pueda "despertar" a la Lambda
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.procesador_eventos.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api_vehicular.execution_arn}/*/*"
}

output "url_para_k6" {
  description = "Copia esta URL en tu script de k6"
  value       = "${aws_apigatewayv2_api.api_vehicular.api_endpoint}/eventos"
}

# 6. Bucket de S3 para el Portal de Resultados (Dashboard)
resource "aws_s3_bucket" "portal_resultados" {
  bucket = "portal-k6-luis-padilla-${random_string.suffix.result}" # Nombre único
}

# Generar un sufijo aleatorio para que el nombre del bucket no choque con otros
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Configuración de Sitio Web Estático
resource "aws_s3_bucket_website_configuration" "portal_config" {
  bucket = aws_s3_bucket.portal_resultados.id

  index_document {
    suffix = "index.html"
  }
}

# Deshabilitar el bloqueo de acceso público (necesario para ver el portal)
resource "aws_s3_bucket_public_access_block" "portal_access" {
  bucket = aws_s3_bucket.portal_resultados.id

  block_public_acls            = false
  block_public_policy          = false
  ignore_public_acls           = false
  restrict_public_buckets      = false
}

# Política para que el profesor pueda ver el index.html vía URL
resource "aws_s3_bucket_policy" "allow_public_access" {
  bucket = aws_s3_bucket.portal_resultados.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.portal_resultados.arn}/*"
      },
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.portal_access]
}

# Output para que Terraform te de la URL del portal al terminar
output "url_del_portal_s3" {
  value = aws_s3_bucket_website_configuration.portal_config.website_endpoint
}