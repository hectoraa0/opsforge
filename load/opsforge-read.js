// OpsForge v0.8: bounded, read-only workload for a LOCAL Kind port-forward.
// Never point this lab at a publicly accessible application.
import http from 'k6/http';
import { check } from 'k6';

function boundedInt(name, fallback, min, max) {
  const raw = __ENV[name];
  const value = raw === undefined ? fallback : Number(raw);
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new Error(`${name} must be an integer between ${min} and ${max}`);
  }
  return value;
}

const baseUrl = __ENV.OPSFORGE_BASE_URL || 'http://127.0.0.1:8081';
if (!/^http:\/\/(127\.0\.0\.1|localhost|\[::1\]):[0-9]{2,5}$/.test(baseUrl)) {
  throw new Error('Only local loopback HTTP URLs with an explicit port are permitted');
}

const rps = boundedInt('OPSFORGE_RPS', 5, 1, 20);
const durationSeconds = boundedInt('OPSFORGE_DURATION', 30, 10, 120);
const maxVUs = boundedInt('OPSFORGE_MAX_VUS', 8, 2, 12);

export const options = {
  scenarios: {
    readonly_traffic: {
      executor: 'constant-arrival-rate',
      rate: rps,
      timeUnit: '1s',
      duration: `${durationSeconds}s`,
      preAllocatedVUs: Math.min(4, maxVUs),
      maxVUs,
      gracefulStop: '10s',
    },
  },
  thresholds: {
    // Lab reliability gates, NOT a production SLO or performance benchmark.
    http_req_failed: ['rate<0.01'],
    checks: ['rate>0.99'],
    dropped_iterations: ['count==0'],
  },
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

export default function () {
  // Roughly 80% database-backed incident-list reads, 20% DB readiness probes.
  const isIncident = Math.random() < 0.8;
  const path = isIncident ? '/api/v1/incidents?limit=10' : '/health/ready';
  const endpoint = isIncident ? 'incidents' : 'ready';
  const response = http.get(`${baseUrl}${path}`, {
    headers: { 'Cache-Control': 'no-cache' },
    timeout: '5s',
    tags: { endpoint },
  });

  check(response, {
    'HTTP status is 200': (r) => r.status === 200,
    'JSON has expected shape': (r) => {
      if (r.status !== 200) return false;
      try {
        const parsed = r.json();
        return isIncident
          ? Array.isArray(parsed)
          : parsed !== null && parsed.status === 'ready';
      } catch (_) {
        return false;
      }
    },
  });
}
