# Terraform-managed Kubernetes sandbox for OpsForge

**Scope:** a SEPARATE, disposable `opsforge-tf` namespace in the EXISTING `kind-opsforge` cluster. The already working `opsforge` namespace and its PostgreSQL PVC are not managed or imported by Terraform and are not modified by this configuration.

## What Terraform manages

- Namespace `opsforge-tf`
- A randomly generated **sandbox-only** PostgreSQL password
- Kubernetes Secret for database credentials
- Headless PostgreSQL Service, StatefulSet, 1 GiB PVC
- FastAPI Service and Deployment with readiness, liveness, startup checks, resource requests/limits, non-root runtime and DB wait init container

The Kubernetes provider targets the explicit `kind-opsforge` context, never the arbitrary current context. Images use `opsforge-api:kind` which was loaded by the previous Kubernetes lab.

## First run (PowerShell in OpsForge project root)

```powershell
# IMPORTANT: add Terraform state patterns to .gitignore before initializing.
@('', '# Terraform local runtime / secrets', '**/.terraform/', '*.tfstate', '*.tfstate.*', '*.tfplan', '*.tfvars', 'crash.log', 'crash.*.log') | Add-Content .gitignore

kubectl --context kind-opsforge get nodes
kind load docker-image opsforge-api:kind --name opsforge
cd terraform/kind
terraform init
terraform fmt -check
terraform validate
terraform plan -out=opsforge.tfplan
```

**Read the plan** before doing anything else: new resources must have namespace `opsforge-tf`. You should see the new namespace, password, Secret, two Services, StatefulSet, and API Deployment. The plan must NOT propose changing/deleting `opsforge` resources. If errors occur, do not apply and inspect the output.

When reviewed and ready:

```powershell
terraform apply opsforge.tfplan
kubectl --context kind-opsforge -n opsforge-tf get pods,svc,pvc
# Use a separate PowerShell for the next command (keeps running):
kubectl --context kind-opsforge -n opsforge-tf port-forward svc/opsforge-api 8082:8000
```

Open `http://127.0.0.1:8082/docs` or test `http://127.0.0.1:8082/health/ready` in another terminal.

## State and password safety

**Important:** the RANDOM sandbox password is recorded in the local `terraform.tfstate` and possibly plan files, even if displayed as sensitive. Do not commit, upload or share `*.tfstate`, `*.tfplan`, `*.tfvars` or the `.terraform/` directory. Never use a real password here. An unencrypted local state is appropriate ONLY for a private learning lab; production needs a secure state backend, access controls, and professional secret management.

The `opsforge-tf` database is completely SEPARATE: incidents from `opsforge` are not carried over.

## Cleanup (destructive to terraform sandbox data ONLY)

In `terraform/kind`:

```powershell
terraform destroy
```

**WARNING:** this removes `opsforge-tf` and its database/PVC. It does not remove the original `opsforge` namespace, provided you have not changed this configuration. Never `kind delete cluster` if you need either database; Kind cluster deletion can destroy both sets of data.

## Current limitations / production hardening

- The *Kind cluster itself* is not provisioned by Terraform, only workloads in it.
- The Docker image must be built and loaded separately before `terraform apply`.
- A Terraform-managed local Secret is an educational approach, not production secret management.
- The API starts migrations at boot, so it runs one replica with `Recreate`. Move migrations into a dedicated Job before scaling or rolling updates.
- There is no public ingress, TLS, end-user authentication, disaster recovery, or production backup policy.
- GitHub Actions currently does not validate Terraform. Add `terraform fmt`/`validate` and a safe plan workflow in a later milestone.
