import http from 'k6/http';
import { check } from 'k6';

// 1. Configuración exacta exigida en la rúbrica (1000 peticiones, 10 VUs, 30s)
export const options = {
    scenarios: {
        default: {
            executor: 'shared-iterations',
            vus: 10,
            iterations: 1000,
            maxDuration: '30s',
        },
    },
};

// Reemplaza esto con tu URL de invocación de API Gateway (la que termina en /prod/eventos)
const URL_API_GATEWAY = 'https://orp0amvto2.execute-api.us-east-2.amazonaws.com/prod/eventos';

export default function () {
    // 2. Generación aleatoria del tipo de evento
    // El 90% de las veces será "Position", el 10% de las veces será "Emergency"
    const isEmergency = Math.random() < 0.10;
    const eventType = isEmergency ? 'Emergency' : 'Position';
    
    // Generar un número de placa aleatorio para simular la flota
    const randomPlate = `VFH-00${Math.floor(Math.random() * 9)}`;

    // 3. Estructura del Payload solicitada en el documento
    const payload = JSON.stringify({
        type: eventType,
        vehicle_plate: randomPlate,
        coordinates: {
            latitude: 4.6097 + (Math.random() * 0.01), // Simula latitud cerca a Bogotá
            longitude: -74.0817 + (Math.random() * 0.01) // Simula longitud
        },
        status: isEmergency ? 'CRITICAL' : 'OK'
    });

    const params = {
        headers: {
            'Content-Type': 'application/json',
        },
    };

    // 4. Ejecutar la petición POST
    const res = http.post(URL_API_GATEWAY, payload, params);

    // 5. Validar que el API Gateway responde correctamente (HTTP 200)
    check(res, {
        'is status 200': (r) => r.status === 200,
    });
}