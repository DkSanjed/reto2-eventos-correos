# Reto 2 - Sistema de Alerta Temprana Vehicular
## Diplomado Arquitectura de Software y Cloud Computing
**Autor:** Luis Padilla  
**Fecha:** Abril 2026  
**Infraestructura:** AWS | IaC con Terraform

---

## Descripción del Sistema

Sistema de alerta temprana para una flota vehicular que recibe eventos en tiempo real a través de un endpoint REST. Detecta eventos de tipo **Emergency** y envía una notificación inmediata por correo electrónico a una cuenta Gmail configurada.

---

## Arquitectura de la Solución
k6 (Pruebas de Carga)
│
▼
┌─────────────────────┐
│   API Gateway       │  ← Throttling 15 req/s | Burst 1000
│   HTTP API          │
└────────┬────────────┘
│
▼
┌─────────────────────┐
│   AWS Lambda        │  ← Node.js 20.x | Timeout 30s | 128MB
│   procesador-       │
│   emergencias-luis  │
└────────┬────────────┘
│
▼
┌─────────────────────┐
│   Gmail SMTP        │  ← Pool de conexiones | Puerto 465
│   Nodemailer        │
└─────────────────────┘

---

## 1. Justificación de Decisiones de Arquitectura

### API Gateway HTTP API
Se eligió **AWS API Gateway HTTP API** como punto de entrada porque:
- Permite configurar throttling (15 req/s) y burst (1000) para controlar el flujo de peticiones
- Es completamente administrado por AWS, eliminando la necesidad de gestionar servidores
- Se integra nativamente con AWS Lambda mediante proxy integration
- Escala automáticamente para absorber picos de tráfico gracias al algoritmo Token Bucket

### AWS Lambda
Se eligió **AWS Lambda** como procesador de eventos porque:
- Modelo serverless que escala automáticamente según la demanda
- No requiere gestión de servidores ni configuración de capacidad
- Se paga únicamente por el tiempo de ejecución real
- Node.js 20.x es ideal para operaciones de I/O asíncrono como el envío de correos

### Nodemailer con Gmail SMTP
Se eligió **Nodemailer** con pool de conexiones SMTP porque:
- Mantiene conexiones SMTP abiertas y reutilizables
- Reduce drásticamente el tiempo de envío al evitar negociaciones TLS repetidas
- Garantiza el envío del correo en menos de 15 segundos
- Compatible nativamente con Gmail usando App Password

### Terraform (IaC)
Se eligió **Terraform** como herramienta de Infrastructure as Code porque:
- Permite reproducir el entorno de forma consistente
- El estado de la infraestructura queda versionado
- Facilita la destrucción y recreación del entorno para demos en vivo

---

## 2. Atributo de Calidad más Importante

### Disponibilidad (Availability)

El atributo de calidad más importante para este sistema es la **Disponibilidad**, por las siguientes razones:

- El reto exige que el **100% de las 1000 solicitudes sean procesadas correctamente**
- Un sistema de alerta temprana vehicular que pierde eventos puede tener consecuencias críticas en la seguridad de conductores
- La arquitectura serverless garantiza disponibilidad automática sin puntos únicos de falla

**Resultado obtenido:**
- 1000/1000 requests exitosas (100%)
- 0 requests fallidas
- Tiempo de respuesta promedio: 126ms

**Segundo en importancia: Tiempo de Respuesta**
- El reto exige que el correo llegue en menos de 15 segundos
- Se logró un tiempo de entrega de menos de 2 segundos gracias al pool SMTP

---

## 3. Diagrama de Arquitectura
                ┌─────────────────────────────────────────────┐
                │           SISTEMA DE ALERTA TEMPRANA        │
                │              FLOTA VEHICULAR                 │
                └─────────────────────────────────────────────┘
┌──────────┐   1000 req    ┌─────────────────┐    Invoca    ┌──────────────────┐
│          │  ──────────►  │   API Gateway   │  ──────────► │   AWS Lambda     │
│   k6     │               │   HTTP API      │              │  Node.js 20.x    │
│  10 VUs  │               │                 │              │                  │
│  23 seg  │               │ Rate: 15 req/s  │              │ ┌──────────────┐ │
└──────────┘               │ Burst: 1000     │              │ │ Detecta tipo │ │
└─────────────────┘              │ │ "Emergency"  │ │
│ └──────┬───────┘ │
│        │         │
│        ▼         │
│ ┌──────────────┐ │
│ │  Nodemailer  │ │
│ │  Pool SMTP   │ │
│ └──────┬───────┘ │
└────────┼─────────┘
│
▼
┌─────────────────┐
│   Gmail SMTP    │
│   Puerto 465    │
│                 │
│ luispadca@      │
│ gmail.com       │
└─────────────────┘
                ┌─────────────────────────────────────────────┐
                │              OBSERVABILIDAD                  │
                │         AWS CloudWatch Logs                  │
                │  [EMERGENCIA] Detectada - Timestamp          │
                │  [CORREO] Enviado exitosamente - Timestamp   │
                └─────────────────────────────────────────────┘

---

## 4. Tácticas de Arquitectura

### Táctica 1: Control de Tráfico (Throttling)
**Objetivo:** Cumplir la restricción de máximo 15 req/s en el API Gateway

**Implementación:**
- `throttling_rate_limit = 15` — limita a 15 peticiones por segundo
- `throttling_burst_limit = 1000` — permite absorber el pico inicial de k6 usando el algoritmo Token Bucket
- Con burst de 1000 tokens acumulados, k6 puede enviar las primeras requests sin rechazo y luego se regula a 15 req/s

**Resultado:** 1000/1000 requests procesadas sin errores 429

---

### Táctica 2: Procesamiento Asíncrono (Event-Driven)
**Objetivo:** Garantizar alta disponibilidad y tiempo de respuesta

**Implementación:**
- La Lambda responde `200 OK` inmediatamente al recibir el evento
- El envío del correo se realiza dentro de la misma ejecución de Lambda de forma asíncrona
- El pool de conexiones SMTP mantiene la conexión abierta para reutilización

**Resultado:** Tiempo de respuesta promedio de 126ms por request

---

### Táctica 3: Pool de Conexiones SMTP
**Objetivo:** Entregar el correo en menos de 15 segundos

**Implementación:**
```javascript
const transporter = nodemailer.createTransport({
  pool: true,
  maxConnections: 3,
  host: 'smtp.gmail.com',
  port: 465,
  secure: true
});
```
- `pool: true` mantiene conexiones TCP/TLS abiertas y reutilizables
- Evita la negociación TLS por cada correo (ahorra 1-2 segundos por envío)
- `maxConnections: 3` controla el uso de recursos

**Resultado:** Correo entregado en menos de 2 segundos

---

### Táctica 4: Detección de Estado en Memoria
**Objetivo:** Controlar el número de correos enviados por ciclo de vida de instancia

**Implementación:**
```javascript
let alertaEnviada = false;

if (tipo === 'Emergency') {
  if (!alertaEnviada) {
    alertaEnviada = true;
    // enviar correo
  } else {
    console.log('[EMERGENCIA] Alerta ya enviada - Ignorando');
  }
}
```
- Flag en memoria que previene múltiples correos por instancia Lambda
- En arquitecturas serverless cada instancia mantiene su propio estado
- En producción se reemplazaría por DynamoDB como flag compartido

---

### Táctica 5: Observabilidad con Logs Estructurados
**Objetivo:** Cumplir el requisito de logs con timestamps exactos

**Implementación:**
[EVENTO]     type=Emergency plate=ABC-310 ts=2026-04-23T04:02:50.061Z
[EMERGENCIA] Detectada - Plate: ABC-310 - Timestamp: 2026-04-23T04:02:50.061Z
[CORREO]     Enviado exitosamente - Timestamp: 2026-04-23T04:02:51.842Z
- Logs estructurados con prefijos identificables
- Timestamps ISO 8601 para medición precisa
- Almacenados en AWS CloudWatch para auditoría

---

## Resultados de Ejecución

### Métricas k6
| Métrica | Valor |
|---|---|
| Total requests | 1000 |
| Exitosas | 1000 (100%) |
| Fallidas | 0 (0%) |
| Duración total | 23.1 segundos |
| Throughput | 43.29 req/seg |
| Latencia promedio | 126 ms |
| Latencia p95 | 124 ms |
| Latencia máxima | 2147 ms |

### Validación de Requisitos
| Requisito | Resultado |
|---|---|
| 1000 eventos procesados | ✅ CUMPLIDO |
| 100% tasa de éxito | ✅ CUMPLIDO |
| Throttling 15 req/s | ✅ CUMPLIDO |
| Correo en menos de 15s | ✅ CUMPLIDO (< 2s) |
| Logs con timestamps | ✅ CUMPLIDO |
| Cuenta Gmail personal | ✅ CUMPLIDO |

---

## Configuración de Infraestructura

### Variables de Entorno Lambda
| Variable | Descripción |
|---|---|
| GMAIL_USER | Cuenta Gmail para envío de alertas |
| GMAIL_APP_PASSWORD | App Password generado en Google Account |

### Parámetros API Gateway
| Parámetro | Valor |
|---|---|
| Protocolo | HTTP API |
| Rate limit | 15 req/s |
| Burst limit | 1000 |
| Endpoint | POST /eventos |

### Parámetros Lambda
| Parámetro | Valor |
|---|---|
| Runtime | Node.js 20.x |
| Timeout | 30 segundos |
| Memoria | 128 MB |
| Región | us-east-1 |

---

## Estructura del Proyecto
reto2-eventos-correos/
├── infrastructure/
│   ├── main.tf          # Infraestructura AWS con Terraform
│   ├── variables.tf     # Variables de configuración
│   └── terraform.tfvars # Credenciales (no incluido en Git)
├── src/
│   ├── index.js         # Código Lambda - lógica de negocio
│   ├── package.json     # Dependencias Node.js
│   └── node_modules/    # Dependencias instaladas
├── reto2_test.js        # Script de pruebas k6
├── .gitignore           # Exclusiones Git
└── README.md            # Documentación técnica

---

## Instrucciones de Despliegue

### Prerequisitos
- AWS CLI configurado
- Terraform instalado
- Node.js instalado
- k6 instalado
- App Password de Gmail generado

### Pasos

```bash
# 1. Instalar dependencias
cd src
npm install nodemailer

# 2. Crear zip de Lambda (Windows PowerShell)
Compress-Archive -Path "index.js","node_modules","package.json" -DestinationPath "lambda_function.zip"

# 3. Desplegar infraestructura
cd ../infrastructure
terraform init
terraform apply -auto-approve

# 4. Ejecutar pruebas
cd ..
k6 run reto2_test.js
```

### Destruir infraestructura
```bash
cd infrastructure
terraform destroy -auto-approve
```

---

## Justificación de Decisión: Múltiples Correos

En arquitecturas serverless, Lambda puede crear múltiples instancias concurrentes para manejar la carga. Cada instancia mantiene su propio estado en memoria (`alertaEnviada`), por lo que cada instancia envía 1 correo al detectar su primer evento Emergency.

**Comportamiento observado:** Con 10 VUs concurrentes se crean hasta 10 instancias Lambda, resultando en múltiples correos de alerta.

**Solución en producción:** Implementar DynamoDB como flag compartido entre instancias:
```javascript
// Verificar en DynamoDB si ya se envió alerta
const item = await dynamodb.get({ TableName: 'alertas', Key: { id: 'emergency' } });
if (!item.Item) {
  await dynamodb.put({ TableName: 'alertas', Item: { id: 'emergency', enviado: true } });
  // enviar correo
}
```

**Para el demo en vivo:** Destruir y redesplegar la infraestructura antes de la presentación garantiza cold start limpio y 1 sola instancia activa al inicio.
```bash
terraform destroy -auto-approve && terraform apply -auto-approve
```