$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Assert-AdminShell
foreach ($server in Get-NtfyServers) {
    $serviceName = "ntfy-marmoura-$([string]$server.Name)"
    if (-not (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) {
        throw "Missing service: $serviceName"
    }
    Restart-Service -Name $serviceName -Force
}
Start-Sleep -Seconds $ServiceStartupSeconds
& (Join-Path $PSScriptRoot 'verify.ps1')
