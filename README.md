# 🚀 Ingesta de Eventos Vehiculares: Arquitectura Asíncrona
> **Proyecto de Diplomado:** Solución escalable y resiliente procesada mediante arquitectura *Serverless* con notificación vía SMTP.

---

## 🏗️ 1. Arquitectura del Sistema
El sistema utiliza un patrón **Event-Driven** (Guiado por Eventos) para desacoplar la ingesta del procesamiento.

### Flujo de Datos:
`Vehículos (k6)` ➡️ `API Gateway` ➡️ `Amazon SQS` ➡️ `AWS Lambda` ➡️ `SMTP (Gmail)`

* **API Gateway:** Punto de entrada con control de tráfico (Throttling a 15 req/s).
* **Amazon SQS:** Amortiguador (Buffer) que garantiza **cero pérdida de datos**.
* **AWS Lambda:** Procesador asíncrono con concurrencia limitada a 10 instancias.
* **Node.js + Nodemailer:** Lógica de negocio y despacho de alertas críticas.

---

## ⚖️ 2. Decisiones de Arquitectura y "Renuncias" (Trade-offs)
En el diseño se priorizó la **estabilidad** y el **costo** sobre la inmediatez total.

| Decisión Técnica | Renuncia (Trade-off) | Justificación Profesional |
| :--- | :--- | :--- |
| **Arquitectura Asíncrona** | Latencia inmediata (Confirmación de envío) | Evita el colapso del sistema ante ráfagas masivas. La persistencia es prioridad. |
| **Throttling (15 req/s)** | Velocidad punta de ingesta | Protege la infraestructura contra ataques DoS y controla los costos operativos. |
| **Concurrencia (10 Lambdas)** | Tiempo de vaciado de cola | Evita saturar el servidor SMTP de salida y mantiene un flujo constante. |
| **SMTP Externo (Gmail)** | Dependencia de terceros | Flexibilidad para integrarse con sistemas corporativos sin restricciones de Amazon SES. |

---

## 📊 3. Pruebas de Rendimiento (k6)
Se validó la robustez de la solución mediante pruebas de estrés.

* **Escenario:** 1,000 peticiones concurrentes.
* **Usuarios Virtuales (VUs):** 10.
* **Resultado:** **100% de éxito** (Status 200).
* **Observación:** El API Gateway aplicó correctamente el límite de tasa sin afectar la integridad de los datos almacenados en SQS.

> [!TIP]
> Los logs de CloudWatch confirman una latencia de procesamiento promedio de **1 segundo** por evento crítico.

---

## 🔐 4. Configuración y Seguridad
Para proteger la integridad de la solución, se implementaron **Variables de Entorno** (Well-Architected Framework):

```env
EMAIL_USER=usuario@gmail.com
EMAIL_PASS=contraseña_aplicacion_16_digitos
EMAIL_RECEIVER=destino@gmail.com

