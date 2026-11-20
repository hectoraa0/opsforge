# OpsForge v0.8 — Read-only Load Testing with Grafana k6

## Goal

Measure application behavior under **bounded, reproducible local traffic** and record throughput, p95 latency, failures, and dropped iterations. This test does not create/update/delete incidents. It is a **local learning experiment, not proof of production capacity**.

The script uses the `constant-arrival-rate` executor to aim for a configured number of requests per second (RPS). It makes roughly 80% `GET /api/v1/incidents?limit=10` requests (database-backed reads) and 20% `GET /health/ready` requests (database connectivity). It validates both HTTP status and expected JSON shapes.

## Prerequisites

- Docker Desktop and existing Kind cluster (`kind-opsforge`) are running.
- The `opsforge` namespace contains a ready API and PostgreSQL.
- Install Grafana k6 using official Windows instructions:

```powershell
winget install k6 --source winget
```

Close and reopen PowerShell after installing. Verify with `k6 version`.

## Run

In **PowerShell A**, leave this running:

```powershell
kubectl --context kind-opsforge -n opsforge port-forward svc/opsforge-api 8081:8000
```

In **PowerShell B**, change to the OpsForge repository root:

```powershell
Invoke-RestMethod http://127.0.0.1:8081/health/ready
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-load-test.ps1
```

This default test is deliberately small: **5 RPS for 30 seconds**, at most **8 virtual users**, exclusively on localhost. Do not increase the workload until you inspect the first result, background CPU/RAM, and application health.

If the first run is healthy and the laptop remains responsive, you may try a second comparison test:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-load-test.ps1 -Rps 10 -DurationSeconds 30
```

**Limits:** RPS 1–20, duration 10–120 seconds, at most 12 virtual users. The k6 JavaScript itself independently enforces these limits and rejects external non-loopback targets.

## What to record

Each test prints results in the PowerShell console and saves a JSON summary under `load-results/` (which MUST be gitignored). Record in your portfolio notes:

| Metric | Meaning |
|---|---|
| `http_reqs` / `rate` | Achieved number of HTTP requests per second, not necessarily the target |
| `http_req_duration` / `p(95)` | 95th-percentile HTTP request duration (ms) |
| `http_req_failed` / `rate` | Fraction of requests judged unsuccessful by k6 |
| `checks` / `rate` | Fraction of HTTP 200 / JSON checks that passed |
| `dropped_iterations` | Scheduled test iterations that could not start with available VUs |

The script has **example lab reliability thresholds**: fewer than 1% failed requests, more than 99% passed checks, zero dropped iterations. These are not a stated product SLO or guarantee of production performance. A failed threshold is useful evidence; do not blindly loosen it to get a green badge.

**Warning:** Results include time spent going through Windows localhost → `kubectl port-forward` → Kubernetes API. This path has overhead and may become the bottleneck. Do not claim your numbers represent production networking or maximum cluster throughput. Repeat runs at the same workload for meaningful comparisons.

## Keep your machine and data safe

- Don't use any public IP/website. The test rejects non-localhost URLs.
- No POST, PATCH, or DELETE requests; all traffic is read-only.
- The test itself does not change the database, but generating many requests creates application logs and metrics.
- Stop any test with Ctrl+C if RAM/CPU spikes or the laptop becomes unresponsive.
- Do not delete a Kubernetes cluster or namespace to stop a test.
- Only commit the k6 script, PowerShell wrapper, docs, and `.gitignore` change. **Do not commit `load-results/`**.

## Troubleshooting

- **k6 not recognized:** finish installation and open a new PowerShell.
- **API unavailable:** leave `kubectl port-forward` in a different PowerShell and check `/health/ready`.
- **High failure rate:** check `kubectl --context kind-opsforge -n opsforge get pods` and API logs.
- **Low achieved RPS, dropped iterations:** the target or test client cannot sustain the chosen rate; compare CPU/memory and lower the rate.
- **Security:** the endpoints have no user authentication in this lab; use only loopback addresses.

After obtaining local results, publish a concise table of **measured** values and test conditions in the final README, not invented or extrapolated claims.

## Verified load test results

Environment: Windows, Docker Desktop, kind Kubernetes.
Traffic: read-only HTTP requests through kubectl port-forward.
Duration: 30 seconds per test.

| Metric | 5 RPS | 10 RPS |
|---|---:|---:|
| HTTP requests | 151 | 301 |
| Actual RPS | 5.03 | 10.03 |
| Average latency | 4.74 ms | 4.90 ms |
| p95 latency | 6.98 ms | 6.69 ms |
| p99 latency | 8.26 ms | 8.49 ms |
| Maximum latency | 10.16 ms | 71.12 ms |
| HTTP failures | 0% | 0% |
| Dropped iterations | 0 | 0 |

Both tests passed all configured k6 thresholds.

These results demonstrate stability under the tested read-only
loads, not maximum server throughput or production performance.
