param([switch]$IUnderstandThisPublishesToInternet)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if (-not $IUnderstandThisPublishesToInternet) {
    throw 'Funnel publishes ntfy to the internet. Pass -IUnderstandThisPublishesToInternet to continue.'
}
$tailscaleExe = Get-TailscaleExePath
& $tailscaleExe funnel --bg (Get-NtfyServeTarget)
if ($LASTEXITCODE -ne 0) { throw 'tailscale funnel failed.' }
& (Join-Path $PSScriptRoot 'exposure-status.ps1')
