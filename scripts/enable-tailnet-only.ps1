$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$tailscaleExe = Get-TailscaleExePath
$target = Get-NtfyServeTarget
& $tailscaleExe funnel reset | Out-Null
& $tailscaleExe serve --bg $target
if ($LASTEXITCODE -ne 0) { throw 'tailscale serve failed.' }
& (Join-Path $PSScriptRoot 'exposure-status.ps1')
