$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Assert-AdminShell
$ntfyExe = Get-NtfyExePath
if (-not (Test-Path -LiteralPath $ntfyExe)) {
    throw 'Run .\scripts\bootstrap.ps1 before installing services.'
}

Stop-NtfyRepoProcesses
$existingServices = Get-Service -Name 'ntfy-marmoura-*' -ErrorAction SilentlyContinue
foreach ($service in $existingServices) {
    Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
    sc.exe delete $service.Name | Out-Null
}
Start-Sleep -Seconds $ServiceStartupSeconds

foreach ($server in Get-NtfyServers) {
    $name = [string]$server.Name
    $serviceName = "ntfy-marmoura-$name"
    $configPath = Get-InstanceConfigPath $name
    $binaryPath = '"' + $ntfyExe + '" serve --config "' + $configPath + '"'
    New-Service `
        -Name $serviceName `
        -BinaryPathName $binaryPath `
        -DisplayName "ntfy Marmoura $name" `
        -Description "ntfy Marmoura local instance $name" `
        -StartupType Automatic | Out-Null
    Start-Service -Name $serviceName
}

Start-Sleep -Seconds $ServiceStartupSeconds
& (Join-Path $PSScriptRoot 'verify.ps1')
