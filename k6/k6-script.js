// k6 load test — Reto 2
// 1000 iteraciones compartidas entre 10 VUs, máximo 30s.
// Espera salida: checks 100%, http_req_failed 0%.
//
// Uso:
//   k6 run \
//     -e API_URL=https://xxxxx.execute-api.us-east-1.amazonaws.com/prod/events \
//     -e API_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
//     k6/k6-script.js
//
// Obtener la API key después del deploy:
//   terraform output -raw api_key
//
// Variables opcionales:
//   EMERGENCY_MODE   "single" (default) | "rate"
//                    - "single": SOLO la última iteración (la N-ésima) es Emergency.
//                                Las otras N-1 son Position. Sirve para medir
//                                con precisión el delta "último envío en k6 → email"
//                                (la rúbrica del reto). UN solo correo.
//                    - "rate": cada iteración es Emergency con probabilidad
//                              EMERGENCY_RATE. Sirve para pruebas de carga del email.
//   EMERGENCY_RATE   (default 0.05 = 5%; solo aplica si EMERGENCY_MODE=rate)

import http from 'k6/http';
import { check } from 'k6';
import exec from 'k6/execution';

export const options = {
  scenarios: {
    default: {
      executor: 'shared-iterations',
      vus: 10,
      iterations: 1000,
      maxDuration: '30s',
      gracefulStop: '30s',
    },
  },
  thresholds: {
    http_req_failed: ['rate==0.00'],       // 0% fallos — requisito del reto
    checks:          ['rate==1.00'],       // 100% status 200
  },
};

const API_URL = __ENV.API_URL;
if (!API_URL) {
  throw new Error('Falta variable de entorno API_URL. Usa: k6 run -e API_URL=<endpoint> -e API_KEY=<key> k6-script.js');
}

const API_KEY = __ENV.API_KEY;
if (!API_KEY) {
  throw new Error('Falta variable de entorno API_KEY. Obtén la key con: terraform output -raw api_key');
}

const EMERGENCY_MODE = (__ENV.EMERGENCY_MODE || 'single').toLowerCase();
if (!['single', 'rate'].includes(EMERGENCY_MODE)) {
  throw new Error(`EMERGENCY_MODE invalido: "${EMERGENCY_MODE}". Usa "single" o "rate".`);
}
const EMERGENCY_RATE = parseFloat(__ENV.EMERGENCY_RATE || '0.05');
const TOTAL_ITERATIONS = 1000;  // debe coincidir con options.scenarios.default.iterations

function randomPlate() {
  const letters = 'ABCDEFGHJKLMNPRSTUVWXYZ';
  const l = () => letters[Math.floor(Math.random() * letters.length)];
  const n = () => Math.floor(Math.random() * 10);
  return `${l()}${l()}${l()}-${n()}${n()}${n()}`;
}

export default function () {
  // request_seq: índice global 1..N de la iteración en el test (único entre VUs).
  // Se usa en el subject del correo para conteo rápido desde Gmail.
  const requestSeq = exec.scenario.iterationInTest + 1; // 1-indexed para humanos

  // Decisión Emergency vs Position según EMERGENCY_MODE.
  let isEmergency;
  if (EMERGENCY_MODE === 'single') {
    // SOLO la última iteración es Emergency. La rúbrica mide:
    //   tiempo = (último envío k6) → (llegada del correo)
    // y como el último envío k6 ES la única Emergency, la medición es exacta.
    isEmergency = (requestSeq === TOTAL_ITERATIONS);
  } else {
    isEmergency = Math.random() < EMERGENCY_RATE;
  }

  // Log visible en la consola para correlacionar con CloudWatch / Gmail.
  if (isEmergency) {
    console.log(`>>> EMERGENCY sent at iteration ${requestSeq} / ${TOTAL_ITERATIONS} — sent_at=${new Date().toISOString()}`);
  }

  const payload = JSON.stringify({
    type: isEmergency ? 'Emergency' : 'Position',
    vehicle_plate: randomPlate(),
    coordinates: {
      latitude:  (Math.random() * 180 - 90).toFixed(6),
      longitude: (Math.random() * 360 - 180).toFixed(6),
    },
    status: 'OK',
    sent_at: new Date().toISOString(),
    request_seq: requestSeq,
    total_requests: TOTAL_ITERATIONS,
  });

  const res = http.post(API_URL, payload, {
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': API_KEY,
    },
  });

  check(res, { 'is status 200': (r) => r.status === 200 });
}
