$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Assert-AdminShell
$ntfyExe = Get-NtfyExePath
if (-not (Test-Path -LiteralPath $ntfyExe)) {
    throw 'Run .\scripts\bootstrap.ps1 before installing services.'
}

Stop-NtfyRepoProcesses
$servicePrefix = Get-NtfyServicePrefix
$deploymentName = Get-NtfyDeploymentName
$existingServices = Get-Service -Name "$servicePrefix-*" -ErrorAction SilentlyContinue
foreach ($service in $existingServices) {
    Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
    sc.exe delete $service.Name | Out-Null
}
Start-Sleep -Seconds $ServiceStartupSeconds

foreach ($server in Get-NtfyServers) {
    $name = [string]$server.Name
    $serviceName = Get-NtfyServiceName $name
    $configPath = Get-InstanceConfigPath $name
    $binaryPath = '"' + $ntfyExe + '" serve --config "' + $configPath + '"'
    New-Service `
        -Name $serviceName `
        -BinaryPathName $binaryPath `
        -DisplayName "Whispergate $deploymentName $name" `
        -Description "Whispergate local ntfy instance $deploymentName/$name" `
        -StartupType Automatic | Out-Null
    sc.exe failure $serviceName reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
    sc.exe failureflag $serviceName 1 | Out-Null
    Start-Service -Name $serviceName
}

Start-Sleep -Seconds $ServiceStartupSeconds
& (Join-Path $PSScriptRoot 'verify.ps1')
