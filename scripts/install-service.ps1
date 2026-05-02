$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Assert-AdminShell
$config = Get-NtfyConfig
$ntfyExe = Get-NtfyExePath
if (-not (Test-Path -LiteralPath $ntfyExe)) {
    throw 'Run .\scripts\bootstrap.ps1 before installing services.'
}

Stop-NtfyRepoProcesses
foreach ($instance in $config.instances) {
    $name = [string]$instance.name
    $serviceName = "ntfy-marmoura-$name"
    $existing = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($existing) {
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        sc.exe delete $serviceName | Out-Null
    }
}
Start-Sleep -Seconds $ServiceStartupSeconds

foreach ($instance in $config.instances) {
    $name = [string]$instance.name
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
