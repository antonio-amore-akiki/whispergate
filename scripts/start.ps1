$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$ntfyExe = Get-NtfyExePath
if (-not (Test-Path -LiteralPath $ntfyExe)) {
    throw 'Run .\scripts\bootstrap.ps1 before starting ntfy.'
}

foreach ($server in Get-NtfyServers) {
    $name = [string]$server.Name
    $port = Get-NtfyListenPort
    $configPath = Get-InstanceConfigPath $name
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Missing generated server config: $configPath"
    }

    $listener = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($listener) {
        $process = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
        if ($process -and $process.ProcessName -eq 'ntfy' -and $process.Path -eq $ntfyExe) {
            continue
        }
        throw "Port $port is already owned by another process. Run .\scripts\stop.ps1 first."
    }

    $startArgs = @{
        FilePath = $ntfyExe
        ArgumentList = @('serve', '--config', $configPath)
        WindowStyle = 'Hidden'
        RedirectStandardOutput = Get-InstanceLogPath $name 'stdout'
        RedirectStandardError = Get-InstanceLogPath $name 'stderr'
    }
    Start-Process @startArgs
    Start-Sleep -Milliseconds $StartupDelayMilliseconds
}

Write-Output 'Started ntfy Marmoura servers.'
