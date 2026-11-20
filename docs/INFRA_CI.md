# Infrastructure CI — OpsForge v0.4

This milestone adds **independent automated infrastructure checks** while leaving the existing `CI` workflow intact.

## What the GitHub Actions workflow does

File: `.github/workflows/infrastructure.yml`.

### Terraform format and validation
- Uses Terraform 1.17.1 with the repository's `.terraform.lock.hcl`.
- Executes `terraform fmt -check`, `terraform init -backend=false -lockfile=readonly`, and `terraform validate`.
- **Does not apply or destroy anything.** A Kubernetes cluster is not required for this job.
- No Terraform state or generated database credentials are uploaded.

### Kubernetes deployment and recovery
- Runs in a fresh **ephemeral Ubuntu GitHub Actions runner**, not on your Windows laptop.
- Creates its own one-node Kind cluster named `opsforge`.
- Builds the app Docker image from the current commit and loads it into that Kind cluster.
- Creates an isolated, disposable namespace and database Secret using clearly fake CI credentials.
- Deploys PostgreSQL and FastAPI with the same YAML used locally.
- Waits for readiness and runs `scripts/smoke_test.py` against port-forwarded API.
- Deletes the API Pod, waits for Kubernetes to create a replacement, and confirms that an existing PostgreSQL incident still exists afterward.
- Prints diagnostic logs automatically if something fails. The runner and cluster are discarded after the job.

## How to run

Push the three new files, then open **GitHub → Actions → Infrastructure CI**. This workflow runs for infrastructure / app changes and is also manually runnable via **Run workflow**.

### Expected jobs

- `Terraform format and validation` — green
- `Kubernetes deployment and recovery` — green

The existing CI still runs its own Python lint, unit tests and Docker Compose smoke test.

## Security / limitations

- `contents: read` is the only explicitly granted `GITHUB_TOKEN` permission.
- No personal GitHub token, Terraform state, `.env`, production database password or cloud credentials are needed.
- The credentials in `scripts/ci-kind.sh` are throwaway **CI-only** examples and should never be used elsewhere.
- Terraform **format and schema validation** is not a deployed Terraform integration test. A Terraform plan/apply in CI would require a separate controlled, isolated runtime.
- Kind CI checks **Kubernetes** readiness and API recovery; it does not validate public ingress, TLS, backups, scaling across nodes, or cloud deployments.
- Third-party GitHub Actions and Kind/CLI releases are version-tagged rather than SHA-pinned. Consider digest-pinning for supply-chain hardening.
- This workflow intentionally does **not** deploy to any remotely hosted or long-lived environment. Production CD should be designed separately with approvals and scoped credentials.
