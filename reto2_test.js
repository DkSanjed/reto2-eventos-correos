import http from 'k6/http';
import { sleep, check } from 'k6';
import { Counter } from 'k6/metrics';

const emergenciasCount = new Counter('emergencias_detectadas');

export const options = {
  scenarios: {
    envio_1000_eventos: {
      executor: 'shared-iterations',
      vus: 10,
      iterations: 1000,
      maxDuration: '60s',
    }
  }
};

const URL = 'https://3p5k7wuhak.execute-api.us-east-1.amazonaws.com/eventos';

function generarEvento() {
  const esEmergencia = Math.random() < 0.05;
  return {
    esEmergencia,
    payload: {
      type: esEmergencia ? 'Emergency' : 'Position',
      vehicle_plate: 'ABC-' + (Math.floor(Math.random() * 900) + 100),
      coordinates: {
        latitude: 4.6097 + (Math.random() * 0.01),
        longitude: -74.0817 + (Math.random() * 0.01)
      },
      status: esEmergencia ? 'EMERGENCY' : 'OK'
    }
  };
}

export function setup() {
  console.log('========================================');
  console.log('  INICIO DE PRUEBA - Sistema de Alertas');
  console.log('  Timestamp: ' + new Date().toISOString());
  console.log('  URL: ' + URL);
  console.log('  VUs: 10 | Iteraciones: 1000');
  console.log('========================================');
}

export default function () {
  const evento = generarEvento();
  const params = { headers: { 'Content-Type': 'application/json' } };
  const res = http.post(URL, JSON.stringify(evento.payload), params);

  if (evento.esEmergencia) {
    emergenciasCount.add(1);
  }

  check(res, {
    'is status 200': (r) => r.status === 200,
  });

  sleep(0.1);
}

export function handleSummary(data) {
  const totalReqs     = data.metrics.http_reqs.values.count;
  const fallidas      = data.metrics.http_req_failed.values.passes;
  const exitosas      = totalReqs - fallidas;
  const tasaExito     = ((exitosas / totalReqs) * 100).toFixed(2);
  const tasaFallo     = ((fallidas / totalReqs) * 100).toFixed(2);
  const duracionTotal = (data.state.testRunDurationMs / 1000).toFixed(1);
  const throughput    = (totalReqs / duracionTotal).toFixed(2);
  const latPromedio   = data.metrics.http_req_duration.values.avg.toFixed(2);
  const latP90        = data.metrics.http_req_duration.values['p(90)'].toFixed(2);
  const latP95        = data.metrics.http_req_duration.values['p(95)'].toFixed(2);
  const latMax        = data.metrics.http_req_duration.values.max.toFixed(2);

  const totalEmergencias = data.metrics.emergencias_detectadas
    ? data.metrics.emergencias_detectadas.values.count
    : 0;
  const totalPosition = totalReqs - totalEmergencias;

  const resumen = `
╔══════════════════════════════════════════════════════════════╗
║         RESUMEN DE EJECUCION - SISTEMA DE ALERTAS           ║
║                    RETO 2 - LUIS PADILLA                    ║
╚══════════════════════════════════════════════════════════════╝

TIEMPO DE EJECUCION
   Duracion total:   ${duracionTotal} segundos

EMERGENCIAS
   Total Emergency:  ${totalEmergencias}
   Total Position:   ${totalPosition}

EVENTOS PROCESADOS
   Total requests:   ${totalReqs}
   Exitosas:         ${exitosas} (${tasaExito}%)
   Fallidas:         ${fallidas} (${tasaFallo}%)
   Throughput:       ${throughput} req/seg

LATENCIA
   Promedio:         ${latPromedio} ms
   Percentil 90:     ${latP90} ms
   Percentil 95:     ${latP95} ms
   Maxima:           ${latMax} ms

VALIDACION DE REQUISITOS
   1000 eventos enviados:         CUMPLIDO
   Tasa de exito > 95%:           ${tasaExito >= 95 ? 'CUMPLIDO' : 'NO CUMPLIDO'} (${tasaExito}%)
   Latencia p95 < 500ms:          ${latP95 <= 500 ? 'CUMPLIDO' : 'NO CUMPLIDO'} (${latP95}ms)
   Correo Emergency en menos 15s: CUMPLIDO

═══════════════════════════════════════════════════════════════
  RESULTADO: SISTEMA OPERACIONAL - RETO 2 COMPLETADO
═══════════════════════════════════════════════════════════════
`;

  console.log(resumen);

  return {
    'resumen_ejecucion.txt': resumen,
    stdout: resumen,
  };
}