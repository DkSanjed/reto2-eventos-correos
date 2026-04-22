# Reto 2 — Sistema de Alerta Temprana para Flota Vehicular

Sistema serverless en AWS que recibe 1000 eventos de posición/emergencia en 30s, detecta eventos `"Emergency"` en tiempo real y envía un correo de alerta a Gmail en menos de 15 segundos.

**Stack**: API Gateway REST (con API Key) + SQS + Lambda (Python 3.12 en ARM64 Graviton + SnapStart) + SES + CloudWatch. Infraestructura 100% declarada en Terraform.

### Optimizaciones y seguridad (v2)
- **ARM64 Graviton2**: ~20% más rápido y ~20% más barato que x86_64.
- **Lambda SnapStart**: cold start reducido de ~580ms a ~80ms (gratis en Python).
- **API Key + Usage Plan**: endpoint requiere header `x-api-key`; sin key = 403. Throttling del reto (rate=15/s, burst=2000) aplicado por key.
- **Medición de latencia end-to-end (v2.1)**: cada request lleva un `sent_at` generado por el cliente (k6). El email de alerta muestra **3 timestamps** (`sent_at` cliente, `received_at` Lambda, `email_sent_at` post-SES) y los **deltas** calculados, para comparar contra la hora de llegada en Gmail sin necesidad de cronómetro externo.
- **Secuencia por correo (v2.2)**: cada request incluye `request_seq` (1..N) y el subject del correo queda como `🚨 Alerta #0042/1000 - ABC-123`. Permite conteo rápido en Gmail: buscar `subject:"🚨 Alerta #"` → Gmail muestra el total en el selector.

---

## Arquitectura (resumen)

```
k6 ──▶ API Gateway REST (rate=15/s, burst=2000)
          │  (AWS service integration — sin Lambda proxy)
          ▼
     SQS Standard  ◀─── DLQ (maxReceiveCount=3)
          │  (event source mapping: batch=10, window=0s)
          ▼
     Lambda processor (reserved_concurrency=10)
          │
          ├──▶ CloudWatch Logs  (timestamp recepción Emergency)
          └──▶ SES SendEmail ──▶ Gmail
                    └──▶ CloudWatch Logs (timestamp envío)
```

Ver detalle completo en [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Prerrequisitos

- **AWS CLI** configurado (`aws sts get-caller-identity` debe retornar tu cuenta)
- **Terraform** >= 1.6
- **gh CLI** autenticado (solo si vas a crear el repo desde la línea de comandos)
- **k6** para pruebas de carga
- Una **cuenta Gmail** para recibir las alertas
- Cuenta AWS con permisos para API Gateway, Lambda, SQS, SES, IAM, CloudWatch

> ⚠️ **SES Sandbox**: por defecto AWS deja SES en sandbox. Solo puedes enviar correos desde/hacia emails verificados. Para este reto basta con verificar tu Gmail (el mismo se usa como `From` y `To`). Terraform dispara el email de verificación; hay que hacer click en el link antes del primer envío.

---

## Quickstart

```bash
# 1. Copiar y ajustar variables
cd terraform
cp terraform.tfvars.example terraform.tfvars
# editar alert_email_to / alert_email_from con tu Gmail

# 2. Desplegar
terraform init
terraform apply

# 3. Confirmar el email de verificación de SES (revisa tu bandeja de entrada)

# 4. Capturar el endpoint y la API key
terraform output api_endpoint_url
# ej: https://abcd1234.execute-api.us-east-1.amazonaws.com/prod/events
terraform output -raw api_key    # genera una key aleatoria, cópiala

# 5. Smoke test — SIN key debe retornar 403
curl -X POST "$(terraform output -raw api_endpoint_url)" \
  -H "Content-Type: application/json" \
  -d '{"type":"Position"}'
# => {"message":"Forbidden"}

# 5b. Smoke test — CON key debe retornar 200
curl -X POST "$(terraform output -raw api_endpoint_url)" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $(terraform output -raw api_key)" \
  -d '{"type":"Emergency","vehicle_plate":"TEST-001","coordinates":{"latitude":12.345,"longitude":67.890},"status":"OK"}'

# 6. Carga con k6 (1000 iteraciones, 10 VUs, 30s)
cd ..
k6 run \
  -e API_URL="$(cd terraform && terraform output -raw api_endpoint_url)" \
  -e API_KEY="$(cd terraform && terraform output -raw api_key)" \
  k6/k6-script.js
```

### Mismo quickstart en PowerShell (Windows)

PowerShell 5.1 no soporta `&&` ni `\` como continuación, así que los comandos son distintos:

```powershell
# Deploy
cd terraform
Copy-Item terraform.tfvars.example terraform.tfvars
# editar emails en terraform.tfvars con tu editor
terraform init
terraform apply

# Confirmar email de verificación de SES en tu Gmail

# Capturar endpoint y key en variables de entorno
# IMPORTANTE: "terraform output" debe correrse DENTRO de terraform/ (donde vive el state).
# Si lo corres fuera, devuelve un warning "No outputs found" y la var queda con basura.
$env:API_URL = terraform output -raw api_endpoint_url
$env:API_KEY = terraform output -raw api_key

# Verifica que no estén vacías ni contengan "Warning"
$env:API_URL
$env:API_KEY

# Smoke test SIN key (debe devolver 403)
Invoke-WebRequest -Method Post -Uri $env:API_URL -ContentType 'application/json' `
  -Body '{"type":"Position"}' -UseBasicParsing

# Smoke test CON key (debe devolver 200)
Invoke-WebRequest -Method Post -Uri $env:API_URL `
  -Headers @{ 'x-api-key' = $env:API_KEY } `
  -ContentType 'application/json' `
  -Body '{"type":"Emergency","vehicle_plate":"TEST-001","coordinates":{"latitude":12.345,"longitude":67.890},"status":"OK"}' `
  -UseBasicParsing

# Carga con k6 — las vars ya están seteadas, solo volvemos a la raíz
cd ..
k6 run -e API_URL=$env:API_URL -e API_KEY=$env:API_KEY k6/k6-script.js
```

---

## Destroy

```bash
cd terraform
terraform destroy
```

---

## Estructura del repo

```
reto2-fleet-alerts/
├── terraform/              # IaC completa (AWS provider 5.x)
│   ├── versions.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── sqs.tf              # cola principal + DLQ + alarma
│   ├── lambda.tf           # función + event source mapping
│   ├── iam.tf              # roles de mínimo privilegio
│   ├── apigateway.tf       # REST API + integración directa a SQS
│   ├── ses.tf              # email identities
│   ├── cloudwatch.tf       # log groups con retention
│   └── outputs.tf
├── lambda/
│   └── handler.py          # parse SQS + filtra Emergency + SES SendEmail
├── k6/
│   └── k6-script.js        # 1000 iters / 10 VUs / 30s
├── docs/
│   └── ARCHITECTURE.md     # decisiones, atributo de calidad, tácticas, logs
└── scripts/
    ├── deploy.sh
    └── destroy.sh
```

---

## Cumplimiento de requisitos del reto

| Requisito | Cómo se cumple |
|---|---|
| 1000 eventos en 30s, 100% procesados | Burst=2000 absorbe el pico inicial sin throttling. SQS garantiza 0% pérdida. |
| API Gateway rate=15 req/s | `aws_api_gateway_usage_plan.prod.throttle_settings.rate_limit = 15` (aplicado por API key) |
| Máximo 10 instancias de procesadores | `scaling_config.maximum_concurrency = 10` en el event source mapping |
| Detectar eventos "Emergency" | `handler.py` filtra `body["type"] == "Emergency"` |
| Email a Gmail en <15s | **Medido con `sent_at` en k6 + `email_accepted_at` en Lambda**: avg=510 ms, min=397 ms, max=964 ms (n=52 emergencies) para el tramo `sent → SES accept`. Falta sumar SES→Gmail (~1-3s). Total real end-to-end: ~2-5s. |
| Logs con hora exacta | `[EMERGENCY_RECEIVED] ts=...` y `[EMAIL_SENT] ts=... delta_sent_to_received=... delta_ses_call=... delta_total=...` en CloudWatch |

---

## Medición de latencia end-to-end (v2.1)

El sistema reporta los tiempos en **dos lugares**:

**1) Dentro del email** (vista humana) — cada alerta Emergency llega con una tabla:

| Paso | Timestamp (UTC) |
|---|---|
| Request enviado (cliente k6) | `sent_at` |
| Recibido en Lambda | `received_at` |
| Email enviado a SES | `email_sent_at` |

Y debajo, 3 deltas ya calculados:
- `sent → received` (red + API GW + SQS + cola → Lambda)
- `received → email_sent` (procesamiento + SES accept)
- **TOTAL `sent → email_sent`** (este es el número del reto)

Para incluir el tramo final (SES → Gmail), compara `email_sent` con la hora que Gmail muestra en el correo recibido.

**2) En CloudWatch Logs** (vista agregable) — cada `[EMAIL_SENT]` incluye:

```
[EMAIL_SENT] ts=2025-XX-XXTHH:MM:SS.xxxxxx+00:00 message_id=... plate=XXX-000 to=... delta_sent_to_received=123 ms delta_total=456 ms
```

Para extraer todas las latencias y promediarlas:

```bash
aws logs filter-log-events \
  --log-group-name /aws/lambda/reto2-fleet-alerts-processor \
  --filter-pattern "EMAIL_SENT" \
  --query 'events[].message' --output text
```

En PowerShell:

```powershell
aws logs filter-log-events `
  --log-group-name /aws/lambda/reto2-fleet-alerts-processor `
  --filter-pattern "EMAIL_SENT" `
  --query 'events[].message' --output text
```

---

## Comandos útiles

```bash
# Ver logs de Lambda en tiempo real
aws logs tail /aws/lambda/reto2-fleet-alerts-processor --follow

# Filtrar solo eventos Emergency
aws logs tail /aws/lambda/reto2-fleet-alerts-processor --follow --filter-pattern "EMERGENCY_RECEIVED"

# Ver métricas de la cola
aws sqs get-queue-attributes \
  --queue-url "$(cd terraform && terraform output -raw queue_url)" \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible
```
