import boto3
import json
import logging
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ses = boto3.client('ses', region_name='us-east-1')

def lambda_handler(event, context):
    try:
        body = json.loads(event.get('body', '{}'))
    except json.JSONDecodeError:
        return {'statusCode': 400, 'body': json.dumps({'error': 'Invalid JSON'})}

    received_at = datetime.now(timezone.utc).isoformat()

    if body.get('type') == 'Emergency':
        logger.info(f"[EMERGENCY RECEIVED] plate={body.get('vehicle_plate')} status={body.get('status')} at={received_at}")
        send_alert(body, received_at)

    return {
        'statusCode': 200,
        'body': json.dumps({'status': 'ok', 'received_at': received_at})
    }

def send_alert(data, received_at):
    import os
    email = os.environ['ALERT_EMAIL']

    response = ses.send_email(
        Source=email,
        Destination={'ToAddresses': [email]},
        Message={
            'Subject': {'Data': 'Alerta de Emergencia'},
            'Body': {'Text': {'Data': (
                f"Alerta de Emergencia\n\n"
                f"Placa:    {data.get('vehicle_plate')}\n"
                f"Estado:   {data.get('status')}\n"
                f"Evento:   Emergency\n"
                f"Latitud:  {data.get('coordinates', {}).get('latitude')}\n"
                f"Longitud: {data.get('coordinates', {}).get('longitude')}\n"
                f"Recibido: {received_at}"
            )}}
        }
    )

    sent_at = datetime.now(timezone.utc).isoformat()
    logger.info(f"[EMAIL SENT] messageId={response['MessageId']} at={sent_at}")