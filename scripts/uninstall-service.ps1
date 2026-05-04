$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Assert-AdminShell
$servicePrefix = Get-NtfyServicePrefix
$services = Get-Service -Name "$servicePrefix-*" -ErrorAction SilentlyContinue
foreach ($service in $services) {
    Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
    sc.exe delete $service.Name | Out-Null
}
Write-Output "Uninstalled Whispergate services matching $servicePrefix-*"
