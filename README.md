# \# Reto 2: Arquitectura de Eventos y Notificaciones Vehiculares 🚗💨

# 

# Este proyecto implementa una solución escalable y segura en AWS para procesar eventos de vehículos (Normales y Emergencias) utilizando \*\*Infraestructura como Código (IaC)\*\*.

# 

# \## 🚀 Arquitectura

# La solución utiliza los siguientes servicios de AWS:

# \- \*\*Amazon API Gateway (HTTP API):\*\* Punto de entrada con control de tráfico (Throttling).

# \- \*\*AWS Lambda (Node.js 20.x):\*\* Procesamiento lógico de eventos y generación de logs.

# \- \*\*Amazon CloudWatch:\*\* Almacenamiento de logs para auditoría de eventos recibidos.

# 

# 

# 

# \## 🛠️ Restricciones Técnicas Implementadas

# Para garantizar la disponibilidad y el control de costos bajo el presupuesto de créditos de AWS, se configuraron los siguientes límites:

# 1\. \*\*Throttling en API Gateway:\*\* - Tasa de ráfaga: `10` peticiones.

# &#x20;  - Tasa límite: `15` peticiones por segundo.

# 2\. \*\*Concurrencia en Lambda:\*\* Configurada para manejo eficiente de ráfagas de eventos.

# 

# \## 🧪 Pruebas de Carga (k6)

# Se realizaron pruebas de estrés simulando el envío masivo de eventos para validar el comportamiento del sistema.

# 

# \### Resultados Obtenidos:

# \- \*\*Latencia promedio:\*\* \~100ms (Respuesta ultra rápida).

# \- \*\*Control de tráfico:\*\* Se validó que al superar las 15 req/s, el API Gateway responde con estado `429 (Too Many Requests)`, protegiendo la infraestructura.

# \- \*\*Tasa de éxito:\*\* Procesamiento exitoso de eventos dentro de los límites establecidos.

# 

# \## 📦 Cómo desplegar

# 1\. Navegar a la carpeta `infrastructure/`.

# 2\. Ejecutar `terraform init`.

# 3\. Ejecutar `terraform apply`.

# 4\. Copiar la `url\_para\_k6` y pegarla en el script de pruebas.

# 

# \---

# \*\*Autor:\*\* Luis Padilla  

# \*\*Diplomado:\*\* Arquitectura de Software y Cloud Computing

