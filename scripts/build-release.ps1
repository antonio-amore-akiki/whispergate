param([string]$OutputRoot = '')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $RepoRoot 'artifacts/release'
}

& (Join-Path $PSScriptRoot 'check-public-safety.ps1')
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$commit = (& git -C $RepoRoot rev-parse --short HEAD).Trim()
$zipPath = Join-Path $OutputRoot "whispergate-$commit.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
& git -C $RepoRoot archive --format=zip --output $zipPath HEAD
if ($LASTEXITCODE -ne 0) { throw 'git archive failed.' }
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLowerInvariant()
$checksumPath = "$zipPath.sha256"
Set-Content -LiteralPath $checksumPath -Encoding ascii -Value "$hash  $(Split-Path -Leaf $zipPath)"
Write-Output "Release package: $zipPath"
Write-Output "Checksum: $checksumPath"
