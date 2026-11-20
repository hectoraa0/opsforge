# OpsForge v0.5 — Container security + GHCR image publishing

This milestone adds `.github/workflows/container-image.yml` **without replacing** the existing CI or Infrastructure CI workflows. It is scoped to the `main` branch of `hectoraa0/opsforge` and can also be invoked manually from the Actions tab.

## What it does

1. Re-runs Ruff and Python unit tests.
2. Builds **one** `opsforge-api:ci` Docker image from the committed source and applies an OCI source label linking it to this repository.
3. Uses Docker Compose to run **that same image** with a disposable PostgreSQL container and performs the existing integration smoke test.
4. Scans the image with Grype via Anchore's SHA-pinned scan action. **Any CRITICAL finding fails the workflow and blocks publication**. HIGH findings remain in the report and should be investigated (a green checkmark is not proof of zero vulnerabilities).
5. Only after successful tests **and** a successful scan does the job authenticate to GitHub Container Registry (GHCR) using the built-in `GITHUB_TOKEN`, then push **the scanned image**.

The image tags will be:

- `ghcr.io/hectoraa0/opsforge:sha-<full commit SHA>` — commit-addressed tag. Prefer this over a moving tag for deployments. Docker registry tags are mutable unless retention and immutability policies are enforced.
- `ghcr.io/hectoraa0/opsforge:main` — convenience moving tag that updates after each successful publish.

No personal access token (PAT), registry password or database credentials need to be committed to GitHub. CI database credentials are fixed test-only strings, **not production secrets**.

## How to install on Windows (PowerShell)

From the repository root:

```powershell
git add .github/workflows/container-image.yml docs/CONTAINER_RELEASE.md
git diff --cached --check
git diff --cached --name-only
git commit -m "Add container vulnerability gate and GHCR publishing"
git push
```

Then open: `https://github.com/hectoraa0/opsforge/actions` and select **Container Security and GHCR Release**. Other workflows will still run independently. **Do not claim this is CD to your laptop**: GitHub-hosted runners cannot deploy directly to the private Kind cluster on your Windows computer.

If the security workflow fails, click its run and inspect the failing step. Do not disable `fail-build` or bypass critical vulnerabilities merely to make the indicator green. Update affected dependencies or the base image, rerun tests and scan, and document any residual risk.

## Finding the image

After a successful release, use the GitHub package view for the repository/account to inspect the image. GHCR packages can be private by default: if you want other people to download the image anonymously for your portfolio, explicitly switch the package's visibility to public in GitHub package settings (and confirm this does not disclose anything you don't want to publish). The source code's `Public` visibility **does not automatically imply** the package is public.

For a *public* image, and substituting the actual complete SHA from the successful release:

```powershell
docker pull ghcr.io/hectoraa0/opsforge:sha-<full-commit-sha>
```

For a private package, authenticate separately with a limited-scope credential that has `read:packages`. **Never paste a token into a chat or commit it to the repository.**

## Roadmap / limits

- This is **continuous integration + image publishing**, not automatic deployment into Kind or a cloud service.
- Current Python dependencies are constrained by ranges instead of a fully reproducible lock. Rebuilding the same commit later could produce a different image. For later releases add a dependency lock and pin base image by digest, and deploy by published digest.
- Image scanning is a snapshot of currently known vulnerabilities, not a guarantee of safety. Periodic rescans and base-image updates remain necessary.
- Tests currently cover unit and a Docker/PostgreSQL smoke test in this workflow, while the independent infrastructure workflow tests Kubernetes; image publication **does not wait for the other workflow's success**. A future protected release pipeline can coordinate all checks and approvals.
- Release action references are SHA-pinned. Keep them updated via reviewed dependency update PRs.
- Runbook, rollback-by-digest, SBOM and signed build provenance are future hardening steps.
