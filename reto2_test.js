import http from 'k6/http';
import { check, sleep } from 'k6';
// Generador del reporte visual
import { htmlReport } from "https://raw.githubusercontent.com/benc-uk/k6-reporter/main/dist/bundle.js";

export const options = {
  vus: 10,
  duration: '20s', // Suficiente para demostrar el Throttling
};

export default function () {
  // Tu URL de AWS
  const url = 'https://80ynd8w3p3.execute-api.us-east-1.amazonaws.com/eventos';
  
  const payload = JSON.stringify({
    vehicle_plate: `LP-${Math.floor(Math.random() * 999)}`,
    type: Math.random() > 0.8 ? 'Emergency' : 'Normal'
  });

  const params = { headers: { 'Content-Type': 'application/json' } };
  const res = http.post(url, payload, params);

  check(res, {
    'Estado 200 (Éxito)': (r) => r.status === 200,
    'Estado 429 (Limitado por Throttling)': (r) => r.status === 429,
  });

  sleep(0.1);
}

// Genera el archivo index.html automáticamente al final
export function handleSummary(data) {
  return {
    "index.html": htmlReport(data),
  };
}