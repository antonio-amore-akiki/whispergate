param([switch]$ConfirmReset)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if (-not $ConfirmReset) {
    throw 'This deletes local runtime state. Pass -ConfirmReset to continue.'
}
$resolvedRoot = [System.IO.Path]::GetFullPath($RepoRoot)
$resolvedRuntime = [System.IO.Path]::GetFullPath($RuntimeRoot)
if (-not $resolvedRuntime.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Runtime path is outside repo root.'
}
Stop-NtfyRepoProcesses
if (Test-Path -LiteralPath $RuntimeRoot) {
    Remove-Item -LiteralPath $RuntimeRoot -Recurse -Force
}
Write-Output 'Reset Whispergate runtime state.'
