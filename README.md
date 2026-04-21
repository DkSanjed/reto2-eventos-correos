# Reto 2 — Sistema de Alerta Temprana para Flota Vehicular

## Contexto

Sistema serverless en AWS que recibe eventos en tiempo real de una flota vehicular. Cada vehículo reporta su posición y estado continuamente. Cuando se detecta un evento de emergencia (botón de pánico o anomalía de sensor), el sistema envía una alerta por correo electrónico en menos de 15 segundos.

---

## Objetivo

- Recibir y procesar **1000 eventos correctamente** en 30 segundos.
- Detectar eventos de tipo `Emergency` dentro del flujo continuo de datos.
- Enviar una alerta por correo Gmail en **menos de 30 segundos** desde la recepción del evento.
- Cumplir las restricciones técnicas: máximo 15 req/s en API Gateway y máximo 10 instancias Lambda simultáneas.

---

## Arquitectura

```
Vehículos / k6 (1000 eventos en 30s)
         │
         │  POST /events
         ▼
┌──────────────────────────┐
│      API Gateway         │  ← Punto de entrada HTTP
│   Stage: prod            │
│   Rate:  15 req/s        │
│   Burst: 2000 (default)  │
└────────────┬─────────────┘
             │ invoca (AWS_PROXY)
             ▼
┌──────────────────────────┐
│      AWS Lambda          │  ← Lógica de negocio (Python 3.12)
│  reto2-vehicle-events    │
│  Timeout: 30s            │
│  Memory:  128 MB         │
│  Max instancias: 10      │
└────────────┬─────────────┘
             │ solo si type == "Emergency"
             ▼
┌──────────────────────────┐
│      Amazon SES          │  ← Envío de correo de alerta
│  (Simple Email Service)  │
│  Destino: Gmail personal │
└──────────────────────────┘
```

**Flujo de un evento:**

1. k6 envía un POST con datos del vehículo al endpoint de API Gateway.
2. API Gateway valida la tasa de peticiones (máx. 15/s) y reenvía a Lambda.
3. Lambda parsea el JSON y revisa el campo `type`.
4. Si `type == "Emergency"`: registra un log con la hora exacta y envía el correo via SES.
5. Lambda responde `200 OK` con la hora de recepción.

---

## Decisiones de Arquitectura

| Componente | Alternativas consideradas | Por qué se eligió |
|---|---|---|
| **AWS Lambda** | EC2, ECS, Docker | Serverless, escala automático, sin gestión de servidores, costo por uso |
| **API Gateway** | ALB, NLB | Permite configurar rate limit (15 req/s) y burst fácilmente desde Terraform |
| **Amazon SES** | SNS, SendGrid, Gmail SMTP | Servicio nativo de AWS, integración directa con Lambda via SDK, baja latencia |
| **Terraform** | CDK, CloudFormation, consola | Infraestructura como código, reproducible y versionable |

---

## Atributo de Calidad más Importante

**Rendimiento (Performance)**

El reto exige procesar 1000 eventos en 30 segundos con un correo de alerta llegando en menos de 15 segundos. Lambda escala automáticamente hasta 10 instancias concurrentes sin configuración adicional, y SES envía el correo en milisegundos desde la misma ejecución. Esto garantiza latencia mínima de extremo a extremo.

---

## Tácticas de Arquitectura

| Táctica | Cómo se aplica |
|---|---|
| **Throttling** | API Gateway limita a 15 req/s para proteger Lambda de sobrecarga |
| **Escalado automático** | Lambda crea nuevas instancias en paralelo (hasta 10) según la demanda |
| **Event-driven** | Lambda solo actúa cuando recibe un evento; sin polling ni recursos ociosos |
| **Observabilidad** | Logs en CloudWatch con timestamps exactos de recepción y envío del correo |
| **Fail-fast** | Lambda retorna 400 inmediatamente si el JSON es inválido |

---

## Estructura del Proyecto

```
.
├── main.tf          # Infraestructura: Lambda, API Gateway, SES, IAM
├── variables.tf     # Variables configurables
├── outputs.tf       # Salidas tras el deploy (URL del endpoint)
├── lambda/
│   └── handler.py   # Código Python de la función Lambda
└── .gitignore       # Excluye archivos de Terraform del repositorio
```

---

## Formato de los Eventos

El endpoint acepta `POST /events` con dos tipos de payload:

**Evento de posición (no genera alerta):**
```json
{
  "type": "Position",
  "vehicle_plate": "ABC-123",
  "coordinates": {
    "latitude": 12.345,
    "longitude": 67.890
  },
  "status": "OK"
}
```

**Evento de emergencia (dispara correo de alerta):**
```json
{
  "type": "Emergency",
  "vehicle_plate": "VFH-800",
  "coordinates": {
    "latitude": 12.345,
    "longitude": 67.890
  },
  "status": "accidente"
}
```

| Campo | Tipo | Descripción |
|---|---|---|
| `type` | string | `"Position"` o `"Emergency"`. Solo Emergency dispara alerta |
| `vehicle_plate` | string | Placa del vehículo |
| `status` | string | Estado del vehículo |
| `coordinates` | object | Posición GPS |

---

## Correo de Alerta

Cuando se detecta un `Emergency`, se envía un correo con este formato:

```
Asunto: Alerta de Emergencia

Alerta de Emergencia

Placa:    VFH-800
Estado:   accidente
Evento:   Emergency
Latitud:  12.345
Longitud: 67.890
Recibido: 2026-04-20T02:30:00+00:00
```

---

## Logs en CloudWatch

Lambda registra dos eventos clave:

```
# Al recibir un Emergency
[EMERGENCY RECEIVED] plate=VFH-800 status=accidente at=2026-04-20T02:30:00+00:00

# Al enviar el correo exitosamente
[EMAIL SENT] messageId=0102018f... at=2026-04-20T02:30:00.350+00:00
```

---

## Recursos AWS Creados

| Recurso | Nombre | Descripción |
|---|---|---|
| Lambda Function | `reto2-vehicle-events` | Procesa eventos y envía alertas |
| API Gateway REST API | `reto2-fleet-api` | Expone el endpoint `/events` |
| API Gateway Stage | `prod` | Etapa de producción (Rate: 15, Burst: 2000) |
| Usage Plan | `reto2-throttle` | Aplica el límite de 15 req/s |
| IAM Role | `reto2-lambda-role` | Permisos de ejecución y envío SES |
| SES Email Identity | (tu correo) | Correo verificado para enviar alertas |

---

## Variables

| Variable | Descripción | Default |
|---|---|---|
| `aws_region` | Región de AWS | `us-east-1` |
| `alert_email` | Gmail verificado en SES para alertas | (requerido) |
| `lambda_timeout` | Timeout de Lambda en segundos | `30` |
| `lambda_memory` | Memoria de Lambda en MB | `128` |

---

## Deploy

### Requisitos previos

- [Terraform](https://developer.hashicorp.com/terraform/install) instalado
- [AWS CLI](https://aws.amazon.com/cli/) configurado con credenciales válidas
- Un correo Gmail verificado en Amazon SES

### Pasos

```bash
# 1. Inicializar Terraform
GODEBUG=preferIPv4=1 terraform init

# 2. Ver los recursos que se van a crear
GODEBUG=preferIPv4=1 terraform plan -var="alert_email=tu@gmail.com"

# 3. Crear la infraestructura
GODEBUG=preferIPv4=1 terraform apply -var="alert_email=tu@gmail.com"
```

> **Nota:** `GODEBUG=preferIPv4=1` es necesario si tu red no tiene IPv6 funcional (error `no such host`).

Al finalizar, Terraform muestra la URL del endpoint:

```
endpoint_url = "https://xxxxxxxxxx.execute-api.us-east-1.amazonaws.com/prod/events"
```

### Destruir la infraestructura

```bash
GODEBUG=preferIPv4=1 terraform destroy -var="alert_email=tu@gmail.com"
```

---

## Pruebas con k6

El script de k6 envía 1000 iteraciones usando 10 VUs (usuarios virtuales) en 30 segundos, simulando eventos `Position` y `Emergency`.

```
scenarios: (100.00%) 1 scenario, 10 max VUs, 1m0s max duration
  * default: 1000 iterations shared among 10 VUs (maxDuration: 30s)

checks.........................: 100.00% 1000 out of 1000
http_req_failed................: 0.00%   0 out of 1000
http_reqs......................: 1000    35.69/s
vus............................: 10      min=10  max=10
```

**Resultado esperado:** 100% de requests exitosos (`status 200`), 0 fallos.

---

## Restricciones Técnicas

| Restricción | Valor configurado |
|---|---|
| Tasa máxima API Gateway | 15 req/s |
| Burst API Gateway | 2000 (default) |
| Instancias Lambda simultáneas | máx. 10 |
| Timeout Lambda | 30s |
| Tiempo máximo de entrega del correo | < 15s para puntaje máximo |

---

## Rúbrica de Evaluación

| Criterio | Puntos |
|---|---|
| Justificación de Decisiones de Arquitectura | 0.5 |
| Atributo de Calidad más Importante | 0.5 |
| Diagrama de Arquitectura | 0.5 |
| Tácticas de Arquitectura | 1.0 |
| **Subtotal Documentación Técnica** | **2.5** |
| Correo llega en menos de 15 segundos | 2.5 |
| Correo llega entre 15 y 45 segundos | 1.5 |
| Correo llega después de 45 segundos | 0.5 |
| **Subtotal Demostración en Vivo** | **2.5** |
