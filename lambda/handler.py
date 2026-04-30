"""
Lambda handler — Reto 2: Fleet alert early-warning system.

Flow:
  SQS batch ─▶ for each record:
    - parse JSON body
    - log reception timestamp
    - if type == "Emergency": SES SendEmail to configured Gmail, log send timestamp
    - on exception: add messageId to batchItemFailures (ReportBatchItemFailures)

Timestamps que se rastrean (v2.1 — medición de latencia end-to-end):
  sent_at        — generado por el cliente (k6) al momento de crear el request
  received_at    — generado en Lambda al comenzar a procesar el record SQS
  email_sent_at  — generado justo después del SES SendEmail exitoso
  → el email incluye los tres timestamps + los deltas calculados para que
    el usuario pueda comparar contra la hora de llegada en Gmail.

Env vars:
  ALERT_EMAIL_TO   — Gmail destinatario verificado en SES
  ALERT_EMAIL_FROM — Email remitente verificado en SES (mismo Gmail en sandbox)
"""

import json
import logging
import os
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

log = logging.getLogger()
log.setLevel(logging.INFO)

ses = boto3.client("ses")

EMAIL_TO = os.environ["ALERT_EMAIL_TO"]
EMAIL_FROM = os.environ["ALERT_EMAIL_FROM"]


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _parse_iso(ts: str):
    """Parse ISO-8601 string (con o sin 'Z'). Devuelve datetime aware o None."""
    if not ts or not isinstance(ts, str):
        return None
    try:
        # Python 3.12 fromisoformat soporta 'Z' como sufijo, pero por compat:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None


def _delta_ms(t_start: str, t_end: str) -> str:
    """Devuelve '<N> ms' o 'N/A' si alguno de los timestamps es inválido."""
    a = _parse_iso(t_start)
    b = _parse_iso(t_end)
    if a is None or b is None:
        return "N/A"
    ms = (b - a).total_seconds() * 1000.0
    return f"{ms:.0f} ms"


def _build_email_html(
    plate: str,
    status: str,
    coords: dict,
    sent_at: str,
    received_at: str,
    email_sent_at: str,
    request_seq=None,
    total_requests=None,
) -> str:
    lat = coords.get("latitude", "N/A")
    lon = coords.get("longitude", "N/A")

    d_sent_recv = _delta_ms(sent_at, received_at) if sent_at else "N/A (cliente no envió sent_at)"
    d_recv_sent = _delta_ms(received_at, email_sent_at)
    d_total = _delta_ms(sent_at, email_sent_at) if sent_at else "N/A"

    if request_seq is not None and total_requests:
        seq_label = f"#{int(request_seq):04d} / {int(total_requests):04d}"
    elif request_seq is not None:
        seq_label = f"#{int(request_seq):04d}"
    else:
        seq_label = "N/A"

    return f"""
    <html>
      <body style="font-family: Arial, sans-serif; max-width:640px;">
        <h2 style="color:#c0392b;">🚨 Alerta de Emergencia [{seq_label}]</h2>
        <p><strong>Secuencia:</strong> {seq_label}</p>
        <p><strong>Placa:</strong> {plate}</p>
        <p><strong>Estado:</strong> {status}</p>
        <p><strong>Evento:</strong> Emergency</p>
        <p><strong>Coordenadas:</strong> lat={lat}, lon={lon}</p>

        <h3 style="color:#2c3e50; margin-top:24px;">⏱ Medición de latencia (UTC)</h3>
        <table cellpadding="6" cellspacing="0" border="0" style="border-collapse:collapse; font-family: monospace; font-size:13px;">
          <tr style="background:#f4f6f8;">
            <td><strong>Request enviado (cliente)</strong></td>
            <td>{sent_at or "N/A"}</td>
          </tr>
          <tr>
            <td><strong>Recibido en Lambda</strong></td>
            <td>{received_at}</td>
          </tr>
          <tr style="background:#f4f6f8;">
            <td><strong>Email enviado a SES</strong></td>
            <td>{email_sent_at}</td>
          </tr>
        </table>

        <h4 style="color:#2c3e50; margin-top:16px;">Deltas</h4>
        <ul style="font-family: monospace; font-size:13px;">
          <li>sent → received (red + API GW + SQS + Lambda): <strong>{d_sent_recv}</strong></li>
          <li>received → email_sent (procesamiento + SES accept): <strong>{d_recv_sent}</strong></li>
          <li><strong>TOTAL sent → email_sent:</strong> <strong>{d_total}</strong></li>
        </ul>
        <p style="font-size:12px;color:#666;">
          Para medir la latencia end-to-end completa, compara <em>email_sent</em>
          con la hora de llegada que muestra Gmail en este correo.
        </p>

        <hr/>
        <p style="font-size:0.8em;color:#888;">Sistema de alerta temprana — flota vehicular</p>
      </body>
    </html>
    """.strip()


def _send_emergency_email(
    body: dict,
    sent_at: str,
    received_at: str,
) -> tuple:
    """Envía el email y devuelve (email_prepared_at, email_accepted_at).

    email_prepared_at: timestamp embebido en el cuerpo del correo (antes de SES).
    email_accepted_at: timestamp post-SES, refleja la latencia real del SES call
                       (útil para logs/métricas; no se puede inyectar al body).
    """
    plate = body.get("vehicle_plate", "UNKNOWN")
    status = body.get("status", "UNKNOWN")
    coords = body.get("coordinates", {}) or {}
    request_seq = body.get("request_seq")
    total_requests = body.get("total_requests")

    # Pre-SES: se inyecta en el HTML del correo.
    email_prepared_at = _now_iso()

    # Subject con número de secuencia para conteo/búsqueda rápida en Gmail.
    # Ej.: "🚨 Alerta #0042/1000 - ABC-123"
    if request_seq is not None and total_requests:
        subject = f"🚨 Alerta #{int(request_seq):04d}/{int(total_requests):04d} - {plate}"
    elif request_seq is not None:
        subject = f"🚨 Alerta #{int(request_seq):04d} - {plate}"
    else:
        subject = f"🚨 Alerta de Emergencia - {plate}"

    ses.send_email(
        Source=EMAIL_FROM,
        Destination={"ToAddresses": [EMAIL_TO]},
        Message={
            "Subject": {"Data": subject, "Charset": "UTF-8"},
            "Body": {
                "Html": {
                    "Data": _build_email_html(
                        plate, status, coords, sent_at, received_at, email_prepared_at,
                        request_seq=request_seq, total_requests=total_requests,
                    ),
                    "Charset": "UTF-8",
                }
            },
        },
    )
    # Post-SES: SES ya aceptó el mensaje — este es el verdadero "email_sent".
    email_accepted_at = _now_iso()
    return email_prepared_at, email_accepted_at


def lambda_handler(event, context):
    failures = []
    records = event.get("Records", [])
    log.info(f"[BATCH_RECEIVED] size={len(records)} request_id={context.aws_request_id}")

    for record in records:
        message_id = record.get("messageId", "unknown")
        try:
            body = json.loads(record["body"])
            received_at = _now_iso()
            evt_type = body.get("type")
            plate = body.get("vehicle_plate", "UNKNOWN")
            sent_at = body.get("sent_at")  # timestamp opcional del cliente (k6)
            request_seq = body.get("request_seq")

            if evt_type == "Emergency":
                log.info(
                    f"[EMERGENCY_RECEIVED] ts={received_at} "
                    f"sent_at={sent_at or 'N/A'} request_seq={request_seq or 'N/A'} "
                    f"message_id={message_id} plate={plate} payload={json.dumps(body)}"
                )
                email_prepared_at, email_accepted_at = _send_emergency_email(
                    body, sent_at, received_at
                )
                d_sent_recv = _delta_ms(sent_at, received_at) if sent_at else "N/A"
                d_ses_call = _delta_ms(email_prepared_at, email_accepted_at)
                d_total = _delta_ms(sent_at, email_accepted_at) if sent_at else "N/A"
                log.info(
                    f"[EMAIL_SENT] ts={email_accepted_at} "
                    f"request_seq={request_seq or 'N/A'} "
                    f"message_id={message_id} plate={plate} to={EMAIL_TO} "
                    f"delta_sent_to_received={d_sent_recv} "
                    f"delta_ses_call={d_ses_call} delta_total={d_total}"
                )
            else:
                # Position o cualquier otro tipo: log ligero, no email
                log.info(
                    f"[POSITION_RECEIVED] ts={received_at} "
                    f"message_id={message_id} plate={plate}"
                )

        except ClientError as e:
            log.exception(
                f"[SES_ERROR] message_id={message_id} error={e.response.get('Error', {})}"
            )
            failures.append({"itemIdentifier": message_id})
        except Exception as e:
            log.exception(f"[PROCESSING_ERROR] message_id={message_id} error={e}")
            failures.append({"itemIdentifier": message_id})

    return {"batchItemFailures": failures}
