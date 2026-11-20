# OpsForge — 5-minute DevOps portfolio demonstration

This checklist is designed to demonstrate **verified capabilities** without exaggerating the project's scope. Always run commands from the repository root unless specified. Never paste `.env`, Terraform state, Kubernetes Secret output, or real backup archives into a screen recording or portfolio issue.

## 1. Show the automated pipeline (30 seconds)

Open [GitHub Actions](https://github.com/hectoraa0/opsforge/actions). Point out the different jobs for Python/DB tests, Terraform/kind tests, and the image-security scan + GHCR publication. Explain that image publication is gated on the scan result, while **deployment to the local cluster still requires deliberate approval**.

## 2. Show live Kubernetes (45 seconds)

```powershell
kubectl --context kind-opsforge -n opsforge get deployment,pods,svc,pvc
kubectl --context kind-opsforge -n opsforge get deploy opsforge-api -o wide
```

Explain what the Deployment, StatefulSet, PVC, readiness checks, and resource limits do. Do **not** use `kubectl delete namespace` for the demo.

## 3. Show service health and API (30 seconds)

In terminal A, keep `kubectl --context kind-opsforge -n opsforge port-forward svc/opsforge-api 8081:8000` running. In terminal B:

```powershell
Invoke-RestMethod http://127.0.0.1:8081/health/ready
Invoke-RestMethod http://127.0.0.1:8081/api/v1/incidents
```

Open `http://127.0.0.1:8081/docs` for Swagger. No live-data mutation is required.

## 4. Show the release strategy and rollback design (45 seconds)

Explain: GitHub Actions builds/tests/scans/publishes, while `deploy-release.ps1` manually promotes an exact commit-tagged image. It verifies readiness after updating both the API and database-wait init container. `kubectl rollout undo` restores an earlier **Pod template**, not database migrations. A manual rollback was exercised locally.

```powershell
kubectl --context kind-opsforge -n opsforge rollout history deployment/opsforge-api
```

Use only a **preview** unless you explicitly intend an update:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-release.ps1 -CommitSha fad03e4fe7efdd35b15777e0d30783c1eed55e83
```

## 5. Show restore and load-test evidence (45 seconds)

Refer to [BACKUP_RESTORE.md](BACKUP_RESTORE.md): a real PostgreSQL dump was SHA-256 verified and restored into a temporary, separate database, recovering one incident row. Do not open the private dump on screen.

Refer to [LOAD_TESTING.md](LOAD_TESTING.md): local read-only tests reached 5.03 and 10.03 RPS with p95 delays 6.98 ms and 6.69 ms respectively; zero failed requests and dropped iterations. Do not present these as production results.

## 6. Explain what you would improve (30 seconds)

- Move Alembic migrations out of API startup and enable a rolling update with multiple replicas.
- Introduce authentication, TLS, secrets management and network policies for any public deployment.
- Add off-host encrypted backup storage, scheduled backups, retention and independent restores.
- Extend performance testing with writes, repeated trials and realistic networking.

## Resume-ready project summary

**OpsForge — DevOps Infrastructure Lab** | GitHub: https://github.com/hectoraa0/opsforge

- Built a reproducible FastAPI/PostgreSQL environment using Docker Compose, Kubernetes kind and Terraform (separate isolated namespaces).
- Implemented GitHub Actions pipelines for lint/unit/integration tests, Terraform validation, disposable Kubernetes self-healing tests, Grype image scanning and GHCR publishing.
- Automated explicit commit-pinned local deployments with health gates and tested Kubernetes rollout rollback; verified PostgreSQL dump/restore with a real record.
- Benchmarked read-only API requests with k6 at 5 and 10 RPS over 30-second local trials, observing 0% HTTP failures and p95 latency below 7 ms in those trials.

Avoid claiming cloud production deployment, high availability, automatic rollback of database migrations, or maximum throughput: those have not been established by this lab.
