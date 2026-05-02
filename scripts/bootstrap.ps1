$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$config = Get-NtfyConfig
$version = [string]$config.ntfyVersion
$baseHost = [string]$config.host
$scheme = [string]$config.scheme
$upstreamBaseUrl = [string]$config.upstreamBaseUrl
Assert-TailscaleReady -HostName $baseHost
$zipName = "ntfy_$($version)_windows_amd64.zip"
$releaseBase = "https://github.com/binwiederhier/ntfy/releases/download/v$version"
$zipPath = Join-Path $DownloadRoot $zipName
$checksumsPath = Join-Path $DownloadRoot 'checksums.txt'

foreach ($path in @($RuntimeRoot, $DownloadRoot, $BinRoot, $ConfigRoot, $CertRoot)) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
}
foreach ($path in @($AuthRoot, $CacheRoot, $AttachRoot, $LogRoot)) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
}

$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri "$releaseBase/$zipName" -OutFile $zipPath -TimeoutSec 30
Invoke-WebRequest -Uri "$releaseBase/checksums.txt" -OutFile $checksumsPath -TimeoutSec 30
$expected = Get-Content -LiteralPath $checksumsPath |
    Where-Object { $_ -match [regex]::Escape($zipName) } |
    ForEach-Object { ($_ -split '\s+')[0].ToLowerInvariant() } |
    Select-Object -First 1
if (-not $expected) {
    throw "Checksum entry missing for $zipName"
}
$actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLowerInvariant()
if ($actual -ne $expected) {
    throw "Checksum mismatch for $zipName"
}

$extractPath = Join-Path $BinRoot "ntfy_$($version)_windows_amd64"
if (-not (Test-Path -LiteralPath (Join-Path $extractPath 'ntfy.exe'))) {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $BinRoot -Force
}
$ntfyExe = Get-NtfyExePath
if (-not (Test-Path -LiteralPath $ntfyExe)) {
    throw "Missing ntfy.exe after extraction: $ntfyExe"
}

$certPath = Join-Path $CertRoot "$baseHost.crt"
$keyPath = Join-Path $CertRoot "$baseHost.key"
if (-not (Test-Path -LiteralPath $certPath) -or -not (Test-Path -LiteralPath $keyPath)) {
    $tailscaleExe = Get-TailscaleExePath
    & $tailscaleExe cert "--cert-file=$certPath" "--key-file=$keyPath" $baseHost
    if ($LASTEXITCODE -ne 0) {
        throw "tailscale cert failed for $baseHost"
    }
}

$authFile = Join-Path $AuthRoot 'auth.db'
Get-ChildItem -Path $ConfigRoot -Filter '*.server.yml' -File -ErrorAction SilentlyContinue |
    Remove-Item -Force
foreach ($server in Get-NtfyServers) {
    $name = [string]$server.Name
    $port = [int]$server.Port
    $externalPortSuffix = if ($port -eq 443) { '' } else { ":$port" }
    New-Item -ItemType Directory -Force -Path (Join-Path $CacheRoot $name) | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $AttachRoot $name) | Out-Null
    $serverConfig = @(
        "base-url: `"$scheme`://$baseHost$externalPortSuffix`"",
        "upstream-base-url: `"$upstreamBaseUrl`"",
        'listen-http: ""',
        "listen-https: `":$port`"",
        "cert-file: `"$(Convert-ToNtfyPath $certPath)`"",
        "key-file: `"$(Convert-ToNtfyPath $keyPath)`"",
        "cache-file: `"$(Convert-ToNtfyPath (Join-Path $CacheRoot "$name\cache.db"))`"",
        "attachment-cache-dir: `"$(Convert-ToNtfyPath (Join-Path $AttachRoot $name))`"",
        "auth-file: `"$(Convert-ToNtfyPath $authFile)`"",
        'auth-default-access: "deny-all"',
        'enable-login: true',
        'behind-proxy: false'
    )
    Set-Content -Path (Get-InstanceConfigPath $name) -Value $serverConfig -Encoding ascii
}

$primaryConfigPath = Get-PrimaryServerConfigPath
if (-not (Test-Path -LiteralPath $authFile)) {
    New-Item -ItemType File -Force -Path $authFile | Out-Null
    $password = [Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
    $credentialPath = Join-Path $AuthRoot 'operator-credentials.txt'
    Set-Content -Path $credentialPath -Encoding ascii -Value @(
        "user=$($config.defaultUser)",
        "password=$password"
    )
    $env:NTFY_PASSWORD = $password
    & $ntfyExe user --config $primaryConfigPath add ([string]$config.defaultUser) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create ntfy user' }
    Remove-Item Env:\NTFY_PASSWORD -ErrorAction SilentlyContinue
}

foreach ($instance in $config.instances) {
    $topic = [string]$instance.topic
    & $ntfyExe access --config $primaryConfigPath ([string]$config.defaultUser) $topic read-write |
        Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to grant user access to $topic" }
    & $ntfyExe access --config $primaryConfigPath everyone $topic ([string]$config.anonymousPermission) |
        Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to grant anonymous access to $topic" }
}

& $ntfyExe help | Select-Object -First 1 | Out-Null
Write-Output "Bootstrapped ntfy $version in $RuntimeRoot"
