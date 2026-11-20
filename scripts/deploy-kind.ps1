# Deploy OpsForge to an existing local kind cluster named "opsforge".
# Run from Windows PowerShell 5.1 or PowerShell 7.
# All commands use an explicit Kubernetes context to prevent accidental deployment elsewhere.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-ExitCode([string]$step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$step failed with exit code $LASTEXITCODE"
    }
}

$root = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $root '.env'
$expectedContext = 'kind-opsforge'

if (-not (Test-Path -LiteralPath $envPath)) {
    throw 'No .env file found at project root. Keep your existing local .env; do not commit it.'
}

$activeContext = (& kubectl config current-context).Trim()
Assert-ExitCode 'Get kubectl context'
if ($activeContext -ne $expectedContext) {
    throw "Active context is '$activeContext', expected '$expectedContext'. Switch with: kubectl config use-context $expectedContext"
}

$lines = Get-Content -LiteralPath $envPath
$passwordLine = @($lines | Where-Object { $_ -match '^POSTGRES_PASSWORD=' })
if ($passwordLine.Count -ne 1) {
    throw 'Expected exactly one POSTGRES_PASSWORD= line in .env'
}
$password = $passwordLine[0].Substring('POSTGRES_PASSWORD='.Length).Trim()
if (-not $password -or $password -match '^replace-with-') {
    throw 'Set a custom POSTGRES_PASSWORD in .env first'
}
# The Compose README asks for URL-safe passwords. Encode anyway so URI punctuation cannot break DATABASE_URL.
$encodedPassword = [Uri]::EscapeDataString($password)
$dbUrl = "postgresql+psycopg://opsforge:$encodedPassword@opsforge-db:5432/opsforge"

Push-Location $root
try {
    Write-Host '[1/7] Build OpsForge API image with Docker'
    & docker build --tag opsforge-api:kind .
    Assert-ExitCode 'Docker build'

    Write-Host '[2/7] Load image into kind-opsforge (local cluster; no image registry)'
    & kind load docker-image opsforge-api:kind --name opsforge
    Assert-ExitCode 'kind image load'

    Write-Host '[3/7] Create namespace'
    & kubectl --context $expectedContext apply -f '.\k8s\namespace.yaml'
    Assert-ExitCode 'Apply namespace'

    Write-Host '[4/7] Set local Secret from .env (not committed to Git)'
    $secret = @{
        apiVersion = 'v1'
        kind = 'Secret'
        metadata = @{ name = 'opsforge-db'; namespace = 'opsforge' }
        type = 'Opaque'
        stringData = @{ password = $password; database_url = $dbUrl }
    }
    $secretJson = ConvertTo-Json -InputObject $secret -Depth 6 -Compress
    $secretJson | & kubectl --context $expectedContext apply --server-side --field-manager=opsforge-local -f -
    Assert-ExitCode 'Apply database secret'

    Write-Host '[5/7] Create PostgreSQL Service + StatefulSet + PVC'
    & kubectl --context $expectedContext apply -f '.\k8s\postgres.yaml'
    Assert-ExitCode 'Apply PostgreSQL'
    & kubectl --context $expectedContext --namespace opsforge rollout status statefulset/opsforge-db --timeout=180s
    Assert-ExitCode 'PostgreSQL rollout'

    Write-Host '[6/7] Create API Service + Deployment'
    & kubectl --context $expectedContext apply -f '.\k8s\api.yaml'
    Assert-ExitCode 'Apply API'
    # Ensure reruns pick up a rebuilt image even though the local tag stays opsforge-api:kind.
    & kubectl --context $expectedContext --namespace opsforge rollout restart deployment/opsforge-api
    Assert-ExitCode 'Restart API'
    & kubectl --context $expectedContext --namespace opsforge rollout status deployment/opsforge-api --timeout=180s
    Assert-ExitCode 'API rollout'

    Write-Host '[7/7] Show deployed objects'
    & kubectl --context $expectedContext --namespace opsforge get pods,services,pvc
    Assert-ExitCode 'Get deployment status'
    Write-Host ''
    Write-Host 'OK: open another PowerShell and run:'
    Write-Host 'kubectl --context kind-opsforge -n opsforge port-forward svc/opsforge-api 8081:8000'
    Write-Host 'Then open http://127.0.0.1:8081/docs or GET /health/ready'
} finally {
    Pop-Location
}
