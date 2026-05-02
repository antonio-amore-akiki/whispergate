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
$LocalOnlyHosts = 'localhost', '127.0.0.1', '::1'

function Get-NtfyConfig {
    $localConfig = Join-Path $RepoRoot 'config.json'
    if (-not (Test-Path -LiteralPath $localConfig)) {
        throw 'Missing config.json. Copy config.example.json to config.json and set a Tailscale host.'
    }
    $config = Get-Content -LiteralPath $localConfig -Raw | ConvertFrom-Json
    Assert-TailscaleConfig -Config $config
    return $config
}

function Convert-ToNtfyPath {
    param([string]$Path)
    return $Path.Replace('\', '/')
}

function Assert-TailscaleConfig {
    param([object]$Config)
    $hostName = [string]$Config.host
    if (-not $hostName) {
        throw 'config.json host is required.'
    }
    if ($LocalOnlyHosts -contains $hostName.ToLowerInvariant()) {
        throw 'config.json host must be a Tailscale DNS name, not localhost.'
    }
    if ($hostName -notmatch '\.ts\.net$') {
        throw 'config.json host must end with .ts.net.'
    }
    if ([string]$Config.scheme -ne 'https') {
        throw 'config.json scheme must be https.'
    }
}

function Get-TailscaleExePath {
    $command = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if (-not $command) {
        throw 'tailscale.exe is required on PATH.'
    }
    return $command.Source
}

function Assert-TailscaleReady {
    param([string]$HostName)
    $tailscaleExe = Get-TailscaleExePath
    & $tailscaleExe status | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'tailscale status failed.'
    }
    $dnsResult = Resolve-DnsName $HostName -ErrorAction SilentlyContinue
    if (-not $dnsResult) {
        throw "Tailscale host does not resolve: $HostName"
    }
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
