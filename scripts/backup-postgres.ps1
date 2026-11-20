# OpsForge v0.7 — safe logical backup from the manually managed kind environment.
# Designed for Windows PowerShell 5.1 / PowerShell 7.
# Never redirect pg_dump binary stdout through PowerShell: use a file inside the pod + kubectl cp.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$context = 'kind-opsforge'
$namespace = 'opsforge'
$pod = 'opsforge-db-0'
$database = 'opsforge'
$user = 'opsforge'
$root = Split-Path -Parent $PSScriptRoot
$backupDir = Join-Path $root 'backups'

function Assert-NativeSuccess([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step failed (exit code $LASTEXITCODE)" }
}

# Refuse to create locally stored database dumps that Git might accidentally publish.
& git -C $root check-ignore -q -- 'backups/git-safety-check.dump'
if ($LASTEXITCODE -ne 0) {
    throw "Backup path is not gitignored. Add '/backups/' to the repository-root .gitignore before proceeding."
}

$phase = & kubectl --context $context -n $namespace get pod $pod -o 'jsonpath={.status.phase}'
Assert-NativeSuccess 'Check PostgreSQL pod'
if ((($phase | Out-String).Trim()) -ne 'Running') { throw 'PostgreSQL pod is not Running.' }

New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$filename = "opsforge-$stamp.dump"
$local = Join-Path $backupDir $filename
$remote = '/tmp/opsforge-backup-' + [guid]::NewGuid().ToString('N') + '.dump'

try {
    Write-Host '[1/4] Creating a consistent PostgreSQL custom-format dump inside the database Pod...'
    & kubectl --context $context -n $namespace exec $pod -- pg_dump -U $user -d $database --format=custom --no-owner --no-acl --file=$remote
    Assert-NativeSuccess 'pg_dump'

    Write-Host '[2/4] Checking the archive inside PostgreSQL Pod...'
    & kubectl --context $context -n $namespace exec $pod -- pg_restore --list $remote | Out-Null
    Assert-NativeSuccess 'pg_restore --list'

    Write-Host '[3/4] Copying the binary archive to Windows without text conversion...'
    $source = "${namespace}/${pod}:$remote"
    # kubectl cp treats a Windows C:\ absolute path as a remote file specification.
    # Run from the local backup directory and pass only a relative filename.
    Push-Location -LiteralPath $backupDir
    try {
        & kubectl --context $context cp $source ("./" + $filename)
        Assert-NativeSuccess 'kubectl cp'
    } finally {
        Pop-Location
    }
    if (-not (Test-Path -LiteralPath $local) -or (Get-Item -LiteralPath $local).Length -lt 128) {
        throw 'Copied backup is missing or unexpectedly small.'
    }

    Write-Host '[4/4] Recording SHA-256 checksum...'
    $sha = (Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash.ToLowerInvariant()
    "$sha  $filename" | Set-Content -LiteralPath ($local + '.sha256') -Encoding Ascii
    Write-Host 'BACKUP CREATED' -ForegroundColor Green
    Write-Host "Backup: $local"
    Write-Host "Bytes: $((Get-Item -LiteralPath $local).Length)"
    Write-Host "SHA-256: $sha"
    Write-Host 'Treat this dump as sensitive data; do not commit or upload it.'
} finally {
    & kubectl --context $context -n $namespace exec $pod -- rm -f $remote 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Unable to delete the temporary dump inside the Pod.' }
}
