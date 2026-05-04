param([switch]$ResetRuntime)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Get-NtfyConfig | Out-Null
if (Test-Path -LiteralPath $RuntimeRoot) {
    if (-not $ResetRuntime) {
        throw 'Runtime exists. Run update/restart, or pass -ResetRuntime to recreate local state.'
    }
    & (Join-Path $PSScriptRoot 'reset-runtime.ps1') -ConfirmReset
}
& (Join-Path $PSScriptRoot 'bootstrap.ps1')
& (Join-Path $PSScriptRoot 'enable-tailnet-only.ps1')
& (Join-Path $PSScriptRoot 'install-service.ps1')
& (Join-Path $PSScriptRoot 'verify.ps1')
