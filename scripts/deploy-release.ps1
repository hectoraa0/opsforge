# OpsForge local, pull-based Continuous Delivery to the existing kind cluster.
# This script does not grant GitHub access to the user's computer.
# Run from Windows PowerShell 5.1 or PowerShell 7; it can be invoked from any directory.
# Preview by default; -Deploy explicitly authorizes the deployment.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string]$CommitSha,
    [switch]$Deploy
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$context = 'kind-opsforge'
$namespace = 'opsforge' # Intentionally NOT Terraform-managed opsforge-tf.
$deployment = 'opsforge-api'
$cluster = 'opsforge'
$image = 'ghcr.io/hectoraa0/opsforge:sha-' + $CommitSha.ToLowerInvariant()

function Assert-NativeSuccess([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw ("{0} failed (exit code {1})" -f $Step, $LASTEXITCODE)
    }
}

function Get-DeploymentSpec {
    $raw = & kubectl --context $context -n $namespace get deployment $deployment -o json
    Assert-NativeSuccess 'Read Deployment'
    $parsed = ConvertFrom-Json -InputObject ($raw -join "`n")
    return $parsed
}

function Test-ApiHealth {
    # Exec stays INSIDE the API pod; no port-forward, no host-exposed service.
    $check = "import json; from urllib.request import urlopen; d=json.load(urlopen('http://127.0.0.1:8000/health/ready', timeout=5)); assert d == {'status':'ready'}, d; print('API readiness: PASS')"
    & kubectl --context $context -n $namespace exec deployment/$deployment -c api -- python -c $check
    Assert-NativeSuccess 'API health probe'
}

Write-Host 'Checking Kubernetes context and deployment...'
$currentContext = ((& kubectl config current-context) | Out-String).Trim()
Assert-NativeSuccess 'Read current Kubernetes context'
if ($currentContext -ne $context) {
    throw "Active context is '$currentContext', expected '$context'. Use: kubectl config use-context $context"
}

$spec = Get-DeploymentSpec
if ($spec.metadata.namespace -ne $namespace -or $spec.metadata.name -ne $deployment) {
    throw 'Unexpected Deployment target. Aborting.'
}
if ([int]$spec.spec.replicas -ne 1 -or $spec.spec.strategy.type -ne 'Recreate') {
    throw 'Deployment is not the expected one-replica Recreate lab. Review migrations/rollout strategy before updating.'
}

$apiContainer = @($spec.spec.template.spec.containers | Where-Object { $_.name -eq 'api' })
$initContainer = @($spec.spec.template.spec.initContainers | Where-Object { $_.name -eq 'wait-for-db' })
if ($apiContainer.Count -ne 1 -or $initContainer.Count -ne 1) {
    throw 'Expected containers api and wait-for-db are missing. Aborting.'
}
$oldApiImage = [string]$apiContainer[0].image
$oldInitImage = [string]$initContainer[0].image

Write-Host ''
Write-Host 'Deployment preview (no changes yet):'
Write-Host "  Cluster:     $cluster"
Write-Host "  Namespace:   $namespace (manual kubectl environment only)"
Write-Host "  Deployment:  $deployment"
Write-Host "  Current API: $oldApiImage"
Write-Host "  Current init:$oldInitImage"
Write-Host "  New image:   $image"
Write-Host '  Strategy:    Recreate (brief downtime possible)'
Write-Host '  Database:    not redeployed; existing PostgreSQL PVC is retained'
Write-Host ''

if (-not $Deploy) {
    Write-Host 'PREVIEW ONLY. Nothing was downloaded or changed.' -ForegroundColor Cyan
    Write-Host ('To approve: .\scripts\deploy-release.ps1 -CommitSha {0} -Deploy' -f $CommitSha)
    return
}

if ($oldApiImage -eq $image -and $oldInitImage -eq $image) {
    Write-Host 'Target image is already deployed. Checking health...'
    & kubectl --context $context -n $namespace rollout status deployment/$deployment --timeout=180s
    Assert-NativeSuccess 'Current rollout'
    Test-ApiHealth
    Write-Host 'Deployment already matches requested commit; health PASS.' -ForegroundColor Green
    return
}

# The image was published by GitHub Actions after tests and a critical CVE scan.
Write-Host '[1/5] Pulling pinned release from GHCR...'
& docker pull $image
Assert-NativeSuccess 'Docker pull'

Write-Host '[2/5] Loading released image into local kind (no registry credentials in cluster)...'
& kind load docker-image $image --name $cluster
Assert-NativeSuccess 'Kind image load'

$updated = $false
try {
    Write-Host '[3/5] Updating BOTH API and database-wait init-container images...'
    & kubectl --context $context -n $namespace set image deployment/$deployment "api=$image" "wait-for-db=$image"
    Assert-NativeSuccess 'Kubernetes set image'
    $updated = $true

    Write-Host '[4/5] Waiting for rollout...'
    & kubectl --context $context -n $namespace rollout status deployment/$deployment --timeout=180s
    Assert-NativeSuccess 'Rollout status'

    $after = Get-DeploymentSpec
    $newApi = @($after.spec.template.spec.containers | Where-Object { $_.name -eq 'api' })
    $newInit = @($after.spec.template.spec.initContainers | Where-Object { $_.name -eq 'wait-for-db' })
    if ($newApi.Count -ne 1 -or $newInit.Count -ne 1 -or $newApi[0].image -ne $image -or $newInit[0].image -ne $image) {
        throw 'Deployment image verification failed.'
    }

    Write-Host '[5/5] Checking API and database readiness from inside the pod...'
    Test-ApiHealth
    Write-Host "SUCCESS: $image deployed to $namespace." -ForegroundColor Green
    Write-Host 'Terraform-managed namespace opsforge-tf was NOT changed.'
} catch {
    $cause = $_
    Write-Warning "Deployment verification failed: $cause"
    if ($updated) {
        Write-Warning 'Attempting Kubernetes Deployment rollback (database migrations are NOT rolled back)...'
        & kubectl --context $context -n $namespace rollout undo deployment/$deployment
        if ($LASTEXITCODE -eq 0) {
            & kubectl --context $context -n $namespace rollout status deployment/$deployment --timeout=180s
            if ($LASTEXITCODE -eq 0) {
                Write-Warning 'Previous Deployment revision restored; verify API and database compatibility manually.'
            } else {
                Write-Warning 'Rollback initiated but readiness failed; inspect kubectl describe/logs.'
            }
        } else {
            Write-Warning 'Automatic rollback failed; inspect kubectl rollout history.'
        }
    }
    throw $cause
}
