# Run a bounded Grafana k6 load test against an already running local port-forward.
# Does not create or modify incidents and does not touch Terraform/Kubernetes objects.
[CmdletBinding()]
param(
    [ValidateRange(1, 20)]
    [int]$Rps = 5,
    [ValidateRange(10, 120)]
    [int]$DurationSeconds = 30,
    [ValidateRange(2, 12)]
    [int]$MaxVUs = 8,
    [ValidatePattern('^http://(127\.0\.0\.1|localhost):[0-9]{2,5}$')]
    [string]$BaseUrl = 'http://127.0.0.1:8081'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path -Parent $PSScriptRoot
$k6File = Join-Path $projectRoot 'load\opsforge-read.js'
$outDir = Join-Path $projectRoot 'load-results'
$summaryFile = Join-Path $outDir ('opsforge-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

if (-not (Get-Command k6 -ErrorAction SilentlyContinue)) {
    throw 'Grafana k6 is not installed. Run: winget install k6 --source winget; then reopen PowerShell.'
}
if (-not (Test-Path -LiteralPath $k6File)) {
    throw "Cannot find load test script: $k6File"
}

Write-Host "Checking read-only target: $BaseUrl/health/ready"
try {
    $ready = Invoke-RestMethod -Uri "$BaseUrl/health/ready" -Method Get -TimeoutSec 7
} catch {
    throw "The API is unavailable. Start: kubectl --context kind-opsforge -n opsforge port-forward svc/opsforge-api 8081:8000. Details: $($_.Exception.Message)"
}
if ($ready.status -ne 'ready') {
    throw 'Target did not return {"status":"ready"}. No load was generated.'
}

New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$env:OPSFORGE_BASE_URL = $BaseUrl
$env:OPSFORGE_RPS = [string]$Rps
$env:OPSFORGE_DURATION = [string]$DurationSeconds
$env:OPSFORGE_MAX_VUS = [string]$MaxVUs

Write-Host "Running bounded read-only test: $Rps requests/sec for $DurationSeconds seconds; max VUs = $MaxVUs"
Write-Host "Local JSON summary: $summaryFile"

Push-Location $projectRoot
try {
    & k6 run --summary-export "$summaryFile" "$k6File"
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Write-Warning "k6 exit code ${code}: a threshold may have failed; inspect the results before changing the workload."
        exit $code
    }
    Write-Host 'LOAD TEST PASSED lab reliability thresholds.' -ForegroundColor Green
} finally {
    Pop-Location
}
