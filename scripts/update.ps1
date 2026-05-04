param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

& (Join-Path $PSScriptRoot 'check-public-safety.ps1')
$beforeHash = Get-NtfyConfigHash
$beforeCommit = (& git -C $RepoRoot rev-parse HEAD).Trim()
if ($DryRun) {
    Write-Output 'Dry run: git pull, bootstrap when config changes, restart service, verify.'
    Write-Output "Current commit: $beforeCommit"
    Write-Output "Config hash: $beforeHash"
    exit 0
}
& git -C $RepoRoot pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'git pull --ff-only failed.' }
$afterHash = Get-NtfyConfigHash
$afterCommit = (& git -C $RepoRoot rev-parse HEAD).Trim()
$statePath = Get-NtfyStatePath
$stateHash = ''
if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $stateHash = [string]$state.configHash
}
if ($beforeHash -ne $afterHash -or $stateHash -ne $afterHash) {
    & (Join-Path $PSScriptRoot 'bootstrap.ps1')
}
& (Join-Path $PSScriptRoot 'restart-service.ps1')
[pscustomobject]@{ commit = $afterCommit; configHash = $afterHash } |
    ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding ascii
& (Join-Path $PSScriptRoot 'verify.ps1')
