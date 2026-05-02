$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Assert-AdminShell
$config = Get-NtfyConfig
foreach ($instance in $config.instances) {
    $serviceName = "ntfy-marmoura-$([string]$instance.name)"
    if (-not (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) {
        throw "Missing service: $serviceName"
    }
    Restart-Service -Name $serviceName -Force
}
Start-Sleep -Seconds $ServiceStartupSeconds
& (Join-Path $PSScriptRoot 'verify.ps1')
