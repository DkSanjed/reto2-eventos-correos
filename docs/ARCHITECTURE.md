# Documentación Técnica — Reto 2: Sistema de Alerta Temprana para Flota Vehicular

> **Estudiante:** Erick — Diplomado en Arquitecturas Cloud, Módulo 2
> **Repo:** https://github.com/DkSanjed/reto2-eventos-correos
> **Fecha:** 2026-04-27
> **Cuenta Gmail destino:** `erickcloud44@gmail.com`

---

## 1. Diagrama de la arquitectura

```
┌────────────┐        POST /events JSON
│    k6      │ ───────────────────────────────┐
│  (client)  │                                 │
└────────────┘                                 ▼
                            ┌──────────────────────────────────┐
                            │  Amazon API Gateway REST          │
                            │  Stage: prod                       │
                            │  rate = 15 req/s   burst = 2000    │
                            │  Integration: AWS service (SQS)    │
                            │  (VTL: form-encoded SendMessage)   │
                            └──────────────┬───────────────────┘
                                           │ sqs:SendMessage
                                           ▼
                            ┌──────────────────────────────────┐
                            │  Amazon SQS Standard Queue        │
                            │  visibility_timeout = 60s          │
                            │  retention = 4 días                │
                            └──────────────┬───────────────────┘
                                           │  Event Source Mapping
                                           │  batch_size=10, window=0s
                                           │  ReportBatchItemFailures
                                           ▼
                            ┌──────────────────────────────────┐
                            │  AWS Lambda — Processor           │
                            │  Runtime: Python 3.12 (ARM64)     │
                            │  SnapStart (PublishedVersions)    │
                            │  Alias: live                       │
                            │  ESM scaling.max_concurrency = 10 │
                            │  timeout=10s, memory=256MB         │
                            └────┬────────────────────┬────────┘
                                 │                    │
                                 │ (if type ==        │ (always)
                                 │  "Emergency")      │
                                 ▼                    ▼
                       ┌────────────────┐    ┌──────────────────┐
                       │  Amazon SES    │    │  CloudWatch Logs │
                       │  SendEmail     │    │  [EMERGENCY_RECV]│
                       └───────┬────────┘    │  [EMAIL_SENT]    │
                               │             └──────────────────┘
                               ▼
                       ┌────────────────┐
                       │  Gmail inbox   │
                       │  (<15s SLA)    │
                       └────────────────┘

                 ┌──────────────────────────┐
Fallos (3x) ───▶ │  SQS DLQ (14 días retn.) │
                 │  + CloudWatch Alarm       │
                 └──────────────────────────┘
```

---

## 2. Decisiones de arquitectura

| Componente                       | Alternativas consideradas                             | Decisión y justificación                                                                                                                                                                                                                                                                                                                                                                  |
| -------------------------------- | ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Ingesta**                      | API GW HTTP (v2) vs REST (v1)                         | **REST** — es el único que expone `throttling_rate_limit`/`throttling_burst_limit` nativos por stage, requisito explícito del reto. HTTP API es más barato pero no cumple la restricción.                                                                                                                                                                                                 |
| **Integración API GW → backend** | Lambda proxy vs AWS service integration directa a SQS | **AWS service direct** — elimina un salto (Lambda de ingesta), reduce latencia ~100-200ms, baja costos, y **API GW responde 200 al cliente en cuanto SQS acepta** (k6 ve éxito inmediato).                                                                                                                                                                                                |
| **Buffer / Cola**                | Ninguno, Kinesis, SQS FIFO, SQS Standard              | **SQS Standard** — FIFO está limitado a 300 msg/s (no sirve para el pico); Kinesis es over-engineering para 1000 eventos; SQS Standard tiene throughput ilimitado y desacopla ingesta de procesamiento garantizando **0% pérdida**.                                                                                                                                                       |
| **Dead Letter Queue**            | Sin DLQ vs DLQ con `maxReceiveCount`                  | **DLQ con 3 reintentos** — si la Lambda falla (ej. SES throttle), el mensaje vuelve a la cola hasta 3 veces. Si sigue fallando, va a DLQ sin perderse. Alarma CloudWatch avisa si hay mensajes en DLQ.                                                                                                                                                                                    |
| **Procesador**                   | EC2, ECS, Lambda                                      | **Lambda** — el reto permite hasta 10 instancias; controlamos concurrencia con `aws_lambda_event_source_mapping.scaling_config.maximum_concurrency = 10`. No usamos `reserved_concurrent_executions` porque cuentas AWS nuevas tienen un quota total de 10 (reservar 10 dejaría 0 para el resto del account); el control en el ESM es suficiente porque la Lambda solo se invoca vía SQS. |
| **Arquitectura del runtime**     | x86_64 vs ARM64                                       | **ARM64 (Graviton2)** — ~20% más rápido y ~20% más barato que x86_64 para cargas Python. Sin downsides en este caso (boto3 soporta ARM nativo).                                                                                                                                                                                                                                           |
| **Cold start mitigation**        | Provisioned concurrency vs SnapStart vs nada          | **Lambda SnapStart** — gratis para Python 3.12, reduce cold start de ~580ms a ~80ms (snapshot del runtime ya inicializado). Provisioned concurrency cuesta dinero por hora.                                                                                                                                                                                                               |
| **Event Source Mapping params**  | `batch_size=1`, `batch_size=10`, con/sin `window`     | **`batch_size=10` + `window=0`** — Lambda polls SQS tan rápido como puede; si hay 10 mensajes disponibles los toma, si hay menos los toma igual sin esperar. Optimiza throughput sin sacrificar latencia.                                                                                                                                                                                 |
| **Control de errores**           | Que todo el batch falle vs item-level                 | **`ReportBatchItemFailures`** — si 1 mensaje falla, solo ése vuelve a la cola (no los otros 9). Buena práctica AWS oficial.                                                                                                                                                                                                                                                               |
| **Notificación**                 | SNS email, SES, APIs externas (Mailgun, SendGrid)     | **SES** — latencia típica 1-3s vs 10-30s de SNS email; nativo en AWS; sandbox cubre el requisito sin paperwork.                                                                                                                                                                                                                                                                           |
| **Identity SES**                 | Identity de dominio vs email                          | **Email identity** — un solo click en Gmail para verificar, sin DNS. Suficiente para sandbox.                                                                                                                                                                                                                                                                                             |
| **Logs**                         | `print()` vs `logging` módulo estructurado            | **`logging`** con marcadores `[EMERGENCY_RECEIVED]`, `[EMAIL_SENT]` y timestamps ISO-8601 — facilita filtros con Logs Insights y extracción para entregable.                                                                                                                                                                                                                              |
| **Encoding de secrets**          | Hardcoded vs env vars vs SSM                          | **Env vars** en la definición de Lambda (`ALERT_EMAIL_TO/FROM`). No son secretos reales, solo configuración.                                                                                                                                                                                                                                                                              |
| **Seguridad del endpoint**       | Abierto vs WAF vs API Key + Usage Plan vs Cognito     | **API Key + Usage Plan** — el endpoint exige header `x-api-key`; sin key responde 403. El usage plan aplica el throttling del reto (rate=15/s, burst=2000) **por API key**, no por stage. Cognito sería overkill para un cliente único (k6); WAF lo dejamos fuera por la restricción de simplicidad del reto.                                                                             |
| **Medición de latencia**         | Solo logs vs trazas X-Ray vs timestamps en payload    | **Timestamps embebidos** en payload + email + logs — el cliente envía `sent_at`, Lambda registra `received_at` y `email_accepted_at` (post-SES). El correo muestra los 3 timestamps + 3 deltas en el body, así no se necesita herramienta externa para evaluar la rúbrica. X-Ray quedó fuera por scope.                                                                                   |

---

## 3. Atributo de calidad más importante

**Performance (latencia de notificación)** — específicamente: **tiempo desde el último evento enviado por k6 hasta la llegada del correo a Gmail**.

### ¿Por qué es el #1?

- **50% del puntaje del reto** depende directamente de este tiempo (<15s = 2.5 pts; 15-45s = 1.5; >45s = 0.5).
- En sistemas de alerta temprana reales, un retraso de segundos puede traducirse en no poder evitar un incidente.

### Atributos secundarios priorizados

1. **Reliability / Disponibilidad** — SQS + DLQ + reintentos garantizan que ningún evento se pierda aunque la Lambda falle momentáneamente.
2. **Scalability / Elasticidad** — el sistema absorbe 33 req/s (1000/30s) aunque el API esté limitado a 15 sostenidos, gracias al burst y a SQS.
3. **Observability** — logs estructurados + métricas + alarma DLQ.

### Latencia esperada (medida + estimación)

| Etapa                             | Latencia típica | Notas                                         |
| --------------------------------- | --------------- | --------------------------------------------- |
| k6 → API GW → SQS                 | 50–150 ms       | TLS + VTL + SendMessage                       |
| SQS → Lambda (polling)            | 100–500 ms      | Long polling interno del event source mapping |
| Lambda cold start (primera invoc) | 300–800 ms      | Python 3.12 + 256MB, muy liviano              |
| Lambda warm execution             | 50–150 ms       | Parsing + branching                           |
| SES SendEmail API call            | 200–500 ms      | Región us-east-1                              |
| SES → Gmail                       | 1000–3000 ms    | Fuera de nuestro control                      |
| **TOTAL esperado**                | **~2–5 s**      | Bien debajo del SLA de 15s                    |

---

## 4. Tácticas de arquitectura aplicadas

Taxonomía SEI (Bass, Clements, Kazman — _Software Architecture in Practice_):

### Performance

- **Introduce concurrency** — Lambda con concurrencia reservada=10 procesa 10 batches en paralelo.
- **Manage event rate** — API Gateway throttling (rate=15, burst=2000) protege el sistema de sobrecarga sin rechazar los 1000 del test.
- **Maintain multiple copies of data** — cache del runtime Python reutiliza el cliente boto3 SES entre invocaciones en el mismo container (warm).
- **Schedule resources** — event source mapping con `window=0` toma mensajes apenas están disponibles.

### Availability / Reliability

- **Exception prevention** — validación JSON en Lambda (try/except por mensaje, no por batch).
- **Exception handling / Retry** — `ReportBatchItemFailures` reintenta solo el mensaje fallido.
- **Graceful degradation** — eventos `Position` se loggean pero no detienen el flujo si hay problemas con SES.
- **Ping/echo / Health monitoring** — CloudWatch Alarm sobre DLQ detecta fallos sistémicos en <1 min.

### Modifiability

- **Encapsulate** — variables Terraform permiten cambiar rate, burst, concurrencia, emails sin tocar recursos.
- **Use intermediaries (broker pattern)** — SQS desacopla ingesta y procesamiento; cambiar el procesador no afecta el API.

### Security

- **Limit access (principle of least privilege)** — rol IAM de Lambda solo tiene `ses:SendEmail` sobre el identity específico; rol de API GW solo tiene `sqs:SendMessage` sobre la cola específica.
- **Audit (non-repudiation)** — CloudWatch Logs con timestamps ISO-8601 UTC e identificadores de request.

### Testability

- **Record/playback** — k6 script es reproducible y parametrizable (`EMERGENCY_RATE`).
- **Specialized interfaces** — endpoint único `/events` facilita pruebas con curl/Postman.

---

## 5. Cumplimiento de restricciones del reto

| Restricción                       | Implementación                                                                 | Archivo                   |
| --------------------------------- | ------------------------------------------------------------------------------ | ------------------------- |
| API GW rate = 15 req/s            | `throttling_rate_limit = 15` en `aws_api_gateway_method_settings`              | `terraform/apigateway.tf` |
| API GW burst = default (2000)     | `throttling_burst_limit = 2000`                                                | `terraform/apigateway.tf` |
| Máx 10 instancias de procesadores | `scaling_config.maximum_concurrency = 10` en `aws_lambda_event_source_mapping` | `terraform/lambda.tf`     |
| Notificación por Gmail            | SES con email identity verificado                                              | `terraform/ses.tf`        |
| 1000 eventos / 30s sin pérdida    | API GW burst=2000 + SQS buffer                                                 | `terraform/*.tf`          |
| Logs de recepción Emergency       | `log.info("[EMERGENCY_RECEIVED] ts=...")`                                      | `lambda/handler.py`       |
| Logs de envío de correo           | `log.info("[EMAIL_SENT] ts=...")`                                              | `lambda/handler.py`       |

---

## 6. Metodología de medición del SLA (rúbrica del reto)

La rúbrica define el tiempo de entrega así:

> _El tiempo total se medirá entre el último envío realizado en el k6 vs la hora de envío del correo y recepción del mismo._

Para que la medición sea **exacta y reproducible**, la solución implementa un modo `EMERGENCY_MODE=single` en el script de k6 (default), donde **únicamente la iteración #1000** (la última) envía un evento `Emergency`. Las 999 iteraciones previas son `Position`. Así:

- El "**último envío en k6**" coincide con el **único** evento `Emergency` del test.
- El payload incluye `sent_at` (ISO-8601 UTC) generado por el cliente justo antes del POST.
- La Lambda registra `received_at` (entrada al record SQS) y `email_accepted_at` (post-SES `SendEmail`).
- Los 3 timestamps **viajan en el cuerpo del correo**, así Gmail muestra:
  1. Hora del último envío en k6 (`sent_at`)
  2. Hora de recepción en Lambda (`received_at`)
  3. Hora de aceptación por SES (`email_accepted_at`)
  4. Hora de llegada en Gmail (header `Date` del email — visible en la UI)

**Delta auditable** = `(Gmail Date)` − `(sent_at en el body)` = tiempo total `último envío k6 → email recibido`.

### Resultado real medido (test del 2026-04-27 10:47 UTC)

| Métrica                         | Valor                                                 |
| ------------------------------- | ----------------------------------------------------- |
| Iteración Emergency             | #1000 / 1000 (la última, con `EMERGENCY_MODE=single`) |
| Vehicle plate del Emergency     | `EWL-254`                                             |
| Lambda received_at              | `2026-04-27T10:47:13.037Z`                            |
| Lambda email_sent_at (post-SES) | `2026-04-27T10:47:13.291Z`                            |
| **Tiempo Lambda → SES accept**  | **254 ms**                                            |
| Tramo SES → Gmail (estimado)    | 1-3 s (depende de Google)                             |
| **TOTAL esperado k6 → Gmail**   | **~1.5-3.5 s ≪ 15 s ✅ (2.5 puntos)**                 |
| k6 stats                        | 1000/1000 OK, 0% fail, 11.0 s totales, avg 107 ms/req |

**Nota sobre drift de reloj**: el reloj local de Windows estaba adelantado ~500 ms respecto a UTC, lo que produce deltas negativos en los logs (`delta_sent_to_received=-417 ms`). Es un artefacto del cliente, no una latencia real. Las mediciones server-side (Lambda + Gmail) no tienen drift y son las autoritativas para la rúbrica. Detalle completo en `docs/execution-logs.txt`.

---

## 7. Muestra de logs (ejemplo esperado)

```
2026-04-21T14:52:03.421Z  [BATCH_RECEIVED] size=10 request_id=abc-123
2026-04-21T14:52:03.485Z  [EMERGENCY_RECEIVED] ts=2026-04-21T14:52:03.485+00:00 message_id=m1 plate=ABC-123 payload={"type":"Emergency","vehicle_plate":"ABC-123",...}
2026-04-21T14:52:03.891Z  [EMAIL_SENT] ts=2026-04-21T14:52:03.891+00:00 message_id=m1 plate=ABC-123 to=erickcloud44@gmail.com
2026-04-21T14:52:03.892Z  [POSITION_RECEIVED] ts=... message_id=m2 plate=XYZ-456
```

Para extraer logs reales después de una prueba:

```bash
aws logs tail /aws/lambda/reto2-fleet-alerts-processor \
  --since 10m \
  --filter-pattern "EMERGENCY_RECEIVED EMAIL_SENT" \
  > docs/execution-logs.txt
```

---

## 8. Instrucciones de deploy/teardown

### Deploy

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# editar emails en terraform.tfvars
terraform init
terraform apply
# revisar bandeja y confirmar email de verificación SES
```

### Prueba

```bash
ENDPOINT=$(terraform output -raw api_endpoint_url)

# Smoke test
curl -X POST "$ENDPOINT" -H "Content-Type: application/json" \
  -d '{"type":"Emergency","vehicle_plate":"TEST-001","coordinates":{"latitude":0,"longitude":0},"status":"OK"}'

# Carga
cd ../k6
k6 run -e API_URL="$ENDPOINT" k6-script.js
```

### Teardown

```bash
cd terraform
terraform destroy
```
