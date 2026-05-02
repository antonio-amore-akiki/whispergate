$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$RuntimeRoot = Join-Path $RepoRoot 'runtime'
$DownloadRoot = Join-Path $RuntimeRoot 'downloads'
$BinRoot = Join-Path $RuntimeRoot 'bin'
$ConfigRoot = Join-Path $RuntimeRoot 'config'
$CertRoot = Join-Path $RuntimeRoot 'certs'
$AuthRoot = Join-Path $RuntimeRoot 'auth'
$CacheRoot = Join-Path $RuntimeRoot 'cache'
$AttachRoot = Join-Path $RuntimeRoot 'attachments'
$LogRoot = Join-Path $RuntimeRoot 'logs'
$StartupDelayMilliseconds = 500
$ServiceStartupSeconds = 3
$HttpTimeoutSeconds = 5

function Get-NtfyConfig {
    $localConfig = Join-Path $RepoRoot 'config.json'
    $exampleConfig = Join-Path $RepoRoot 'config.example.json'
    $configPath = if (Test-Path -LiteralPath $localConfig) { $localConfig } else { $exampleConfig }
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Missing config file: $configPath"
    }
    return Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
}

function Convert-ToNtfyPath {
    param([string]$Path)
    return $Path.Replace('\', '/')
}

function Get-NtfyExePath {
    $config = Get-NtfyConfig
    $version = [string]$config.ntfyVersion
    return Join-Path $BinRoot "ntfy_$($version)_windows_amd64\ntfy.exe"
}

function Get-InstanceConfigPath {
    param([string]$Name)
    return Join-Path $ConfigRoot "$Name.server.yml"
}

function Get-InstanceLogPath {
    param([string]$Name, [string]$Kind)
    return Join-Path $LogRoot "$Name.$Kind.log"
}

function Get-ConfiguredPorts {
    $config = Get-NtfyConfig
    return @($config.instances | ForEach-Object { [int]$_.port })
}

function Assert-AdminShell {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator
    if (-not $principal.IsInRole($adminRole)) {
        throw 'Run this command from an elevated Administrator PowerShell.'
    }
}

function Stop-NtfyRepoProcesses {
    $ports = Get-ConfiguredPorts
    $pids = @()
    foreach ($port in $ports) {
        $listeners = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
        foreach ($listener in $listeners) {
            $pids += [int]$listener.OwningProcess
        }
    }
    foreach ($processId in ($pids | Sort-Object -Unique)) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($process -and $process.ProcessName -eq 'ntfy') {
            Stop-Process -Id $processId -Force
        }
    }
}
