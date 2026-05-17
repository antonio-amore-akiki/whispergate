param([switch]$ConfirmReset)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if (-not $ConfirmReset) {
    throw 'This deletes local runtime state. Pass -ConfirmReset to continue.'
}
$resolvedRoot = [System.IO.Path]::GetFullPath($RepoRoot)
$resolvedRuntime = [System.IO.Path]::GetFullPath($RuntimeRoot)
$resolvedLocalAppData = [System.IO.Path]::GetFullPath([Environment]::GetFolderPath('LocalApplicationData'))
if (-not $resolvedRuntime.StartsWith($resolvedLocalAppData, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Runtime path is outside LocalAppData.'
}
Stop-NtfyRepoProcesses
if (Test-Path -LiteralPath $RuntimeRoot) {
    Remove-Item -LiteralPath $RuntimeRoot -Recurse -Force
}
Write-Output 'Reset Whispergate runtime state.'
