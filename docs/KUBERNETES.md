# OpsForge on Kubernetes (local kind cluster)

This folder adds an independently reproducible **local** Kubernetes deployment to OpsForge. It is a learning environment, not a public production service.

## Requirements

- Docker Desktop (Linux containers); `docker`, `kind`, `kubectl` in PATH.
- Existing Kind cluster `opsforge` and context `kind-opsforge` (`kubectl get nodes` must show `Ready`).
- An existing local `.env` in the OpsForge root with `POSTGRES_PASSWORD=...` (never commit this file).
- Run from Windows PowerShell, from the **OpsForge repository root**.

## Deploy

Stop the Docker Compose version first to reduce RAM use. It has **separate database storage**; existing Compose incidents will not be copied to Kubernetes.

```powershell
# Optional, only if Compose is running:
docker compose --profile observability stop

# Inspect the script, then run it:
Get-Content .\scripts\deploy-kind.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-kind.ps1
```

The script confirms the active context is `kind-opsforge`, builds the image from the current code, loads it into Kind, creates a namespace and a Secret **from the local `.env`**, and applies the manifests. It waits for PostgreSQL and the API to be ready and prints a status summary. Nothing is pushed to Docker Hub.

**Important:** Kubernetes secrets are only base64-encoded inside the cluster and should not be treated as secure at-rest encryption by default. This approach is for an isolated local sandbox. The Secret's plaintext is never written into Git-tracked files. For cloud/production, use dedicated secret management, encryption, access policies, and credentials rotation.

## Access the API

Run in a separate PowerShell window (leave the port-forward running):

```powershell
kubectl --context kind-opsforge -n opsforge port-forward svc/opsforge-api 8081:8000
```

Now use <http://127.0.0.1:8081/docs> or test in another window:

```powershell
Invoke-RestMethod http://127.0.0.1:8081/health/ready
$body = @{title='Kind deployment smoke test'; severity='low'} | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8081/api/v1/incidents -ContentType 'application/json' -Body $body
Invoke-RestMethod http://127.0.0.1:8081/api/v1/incidents
```

## Diagnosis

```powershell
kubectl --context kind-opsforge -n opsforge get pods,svc,pvc
kubectl --context kind-opsforge -n opsforge describe pods
kubectl --context kind-opsforge -n opsforge logs deploy/opsforge-api --tail=100
kubectl --context kind-opsforge -n opsforge logs statefulset/opsforge-db --tail=100
```

All images, Secrets, Pods and storage stay on your laptop. The database stores data in a Kind local PersistentVolumeClaim (PVC), so data survives **Pod restarts**. Destroying the Kind cluster may destroy that data. The Compose volume is separate and is not affected by deleting the Kind cluster.

## Demonstrate self-healing

After successful deployment:

```powershell
kubectl --context kind-opsforge -n opsforge delete pod -l app.kubernetes.io/name=opsforge-api
kubectl --context kind-opsforge -n opsforge rollout status deploy/opsforge-api --timeout=120s
kubectl --context kind-opsforge -n opsforge get pods
```

The Deployment controller should create a replacement Pod. For future production-oriented work, move database migrations into a single managed Job so multiple replicas can be deployed with rolling updates, use proper DB backup/restore, isolate network traffic with NetworkPolicies, and integrate load testing and metrics into CI.

## Why `Recreate` instead of rolling update?

The current API runs Alembic migrations at container startup. One replica and `Recreate` avoid running two migrations in parallel during a deployment. We will move schema migrations to a separate Kubernetes Job before adding a second API replica or rolling-update strategy.

## Local resources and cleanup

These manifests request approximately 224 MiB of memory requests across the running API and database containers, plus database page cache, image layers and the Kubernetes control-plane. Limits are **not** guaranteed usage amounts. Verify actual usage with Docker Desktop/Task Manager and `docker stats --no-stream`.

To remove only application workloads while keeping the cluster:

```powershell
kubectl --context kind-opsforge delete namespace opsforge
```

**Warning:** deleting the namespace also deletes its PostgreSQL PVC and its data. For routine restarts, stop Docker Desktop after your work instead; don't delete the cluster or namespace.
