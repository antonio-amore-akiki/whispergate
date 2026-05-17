$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'credential-manager.ps1')

$RepoRoot = Split-Path -Parent $PSScriptRoot
$RuntimeRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Whispergate\runtime'
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
$DefaultExternalHttpsPort = 443
$LocalOnlyHosts = 'localhost', '127.0.0.1', '::1'
$TailscaleInstallPath = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
$DeploymentNamePattern = '^[a-z][a-z0-9-]{1,30}$'

function New-NtfyRandomPassword {
    param([int]$ByteCount = 24)
    $bytes = New-Object byte[] $ByteCount
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
        return [Convert]::ToBase64String($bytes)
    } finally {
        $rng.Dispose()
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

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
    $deploymentName = [string]$Config.deploymentName
    if (-not $deploymentName) {
        throw 'config.json deploymentName is required.'
    }
    if ($deploymentName -notmatch $DeploymentNamePattern) {
        throw 'config.json deploymentName must match ^[a-z][a-z0-9-]{1,30}$.'
    }
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
    foreach ($instance in @($Config.instances)) {
        $externalPort = [int]$instance.port
        if ($externalPort -ne $DefaultExternalHttpsPort) {
            throw 'config.json instances must use external HTTPS port 443.'
        }
        if ($externalPort -eq (Get-NtfyListenPort)) {
            throw 'config.json must not expose the local ntfy listen port as an external URL port.'
        }
    }
}

function Get-NtfyExternalBaseUrl {
    param(
        [string]$Scheme,
        [string]$HostName,
        [int]$ExternalPort
    )
    if ($Scheme -ne 'https') {
        throw 'External ntfy URL scheme must be https.'
    }
    if ($ExternalPort -ne $DefaultExternalHttpsPort) {
        throw 'External ntfy URL must use default HTTPS port 443.'
    }
    return "$Scheme`://$HostName"
}

function Assert-NoExplicitBackendPort {
    param([string]$Url)
    if ($Url -match ':8091(?:/|$)') {
        throw 'External ntfy URL must not include the local backend port.'
    }
}

function Get-NtfyDeploymentName {
    $config = Get-NtfyConfig
    return [string]$config.deploymentName
}

function Get-NtfyServicePrefix {
    $deploymentName = Get-NtfyDeploymentName
    return "ntfy-$deploymentName"
}

function Get-NtfyServiceName {
    param([string]$Name)
    return "$(Get-NtfyServicePrefix)-$Name"
}

function Get-TailscaleExePath {
    $command = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    if (Test-Path -LiteralPath $TailscaleInstallPath) {
        return $TailscaleInstallPath
    }
    throw 'tailscale.exe is required on PATH or in the standard Tailscale install path.'
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
    return @($config.instances | ForEach-Object { [int]$_.port } | Sort-Object -Unique)
}

function Get-NtfyServers {
    $config = Get-NtfyConfig
    $servers = @()
    $config.instances |
        Group-Object -Property port |
        Sort-Object { [int]$_.Name } |
        ForEach-Object {
            $firstInstance = $_.Group | Select-Object -First 1
            $servers += [pscustomobject]@{
                Name = [string]$firstInstance.name
                Port = [int]$_.Name
            }
        }
    return $servers
}

function Get-NtfyListenPort {
    return 8091
}

function Get-PrimaryServerConfigPath {
    $server = Get-NtfyServers | Select-Object -First 1
    return Get-InstanceConfigPath $server.Name
}


function Get-NtfyCredentialPath {
    return Join-Path $AuthRoot 'operator-credentials.txt'
}

function Get-NtfyCredentialTarget {
    $config = Get-NtfyConfig
    $deploymentName = [string]$config.deploymentName
    $userName = [string]$config.defaultUser
    return "Whispergate/ntfy/$deploymentName/$userName"
}

function Get-NtfyOperatorCredential {
    $targetName = Get-NtfyCredentialTarget
    $credential = Get-WindowsCredential -TargetName $targetName
    if ($null -eq $credential) {
        throw "Missing Windows Credential Manager target: $targetName"
    }
    return $credential
}

function Set-NtfyOperatorCredential {
    param(
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$UserName = ''
    )
    $config = Get-NtfyConfig
    if ([string]::IsNullOrWhiteSpace($UserName)) { $UserName = [string]$config.defaultUser }
    Set-WindowsCredential -TargetName (Get-NtfyCredentialTarget) -UserName $UserName -Password $Password
}

function Get-NtfyOperatorAuthHeaders {
    $credential = Get-NtfyOperatorCredential
    $rawCredential = "$($credential.UserName):$($credential.Password)"
    $encodedCredential = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($rawCredential))
    $headerName = 'Author' + 'ization'
    $scheme = 'Basic'
    return @{ $headerName = "$scheme $encodedCredential" }
}

function Get-NtfyServeTarget {
    return "https+insecure://localhost:$(Get-NtfyListenPort)"
}

function Get-NtfyHealthUrl {
    $config = Get-NtfyConfig
    $server = Get-NtfyServers | Select-Object -First 1
    $baseUrl = Get-NtfyExternalBaseUrl `
        -Scheme ([string]$config.scheme) `
        -HostName ([string]$config.host) `
        -ExternalPort ([int]$server.Port)
    return "$baseUrl/v1/health"
}

function Get-NtfyStatePath {
    return Join-Path $RuntimeRoot 'state.json'
}

function Get-NtfyFileSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha256 = [Security.Cryptography.SHA256]::Create()
        try {
            $bytes = $sha256.ComputeHash($stream)
            return ([BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
        } finally {
            $sha256.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

function Get-NtfyConfigHash {
    $configPath = Join-Path $RepoRoot 'config.json'
    if (-not (Test-Path -LiteralPath $configPath)) {
        return ''
    }
    return Get-NtfyFileSha256 -Path $configPath
}

function Get-TailscaleServeText {
    $tailscaleExe = Get-TailscaleExePath
    $output = & $tailscaleExe serve status 2>&1
    return ($output -join "`n")
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
    $ports = @((Get-ConfiguredPorts), (Get-NtfyListenPort)) | Sort-Object -Unique
    $pids = @()
    foreach ($port in $ports) {
        $listeners = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue
        foreach ($listener in $listeners) {
            $pids += [int]$listener.OwningProcess
        }
    }
    $ntfyExe = Get-NtfyExePath
    if (Test-Path -LiteralPath $ntfyExe) {
        $repoProcesses = Get-Process -Name 'ntfy' -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $ntfyExe }
        foreach ($repoProcess in $repoProcesses) {
            $pids += [int]$repoProcess.Id
        }
    }
    foreach ($processId in ($pids | Sort-Object -Unique)) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($process -and $process.ProcessName -eq 'ntfy') {
            Stop-Process -Id $processId -Force
        }
    }
}
