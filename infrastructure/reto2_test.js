import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  // Configuración para simular la carga
  vus: 200,          // 10 usuarios virtuales atacando al tiempo
  duration: '10s',  // El test durará 30 segundos
};

export default function () {
  // 1. TU URL de AWS (La que generó Terraform)
  const url = 'https://80ynd8w3p3.execute-api.us-east-1.amazonaws.com/eventos';

  // 2. Datos simulados del vehículo
  const payload = JSON.stringify({
    vehicle_plate: `ABC-${Math.floor(Math.random() * 999)}`, // Placa aleatoria
    type: Math.random() > 0.7 ? 'Emergency' : 'Normal',    // 30% de emergencias
    timestamp: new Date().toISOString()
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };

  // 3. Enviamos la petición POST
  const res = http.post(url, payload, params);

  // 4. Verificaciones
  check(res, {
    'es estado 200 (OK)': (r) => r.status === 200,
    'es estado 429 (Limitado)': (r) => r.status === 429,
  });

  // Pequeña espera entre envíos para no saturar de golpe tu internet
  sleep(0.1); 
}