$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$config = Get-NtfyConfig
$version = [string]$config.ntfyVersion
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

$certPath = Join-Path $CertRoot 'localhost.crt'
$keyPath = Join-Path $CertRoot 'localhost.key'
if (-not (Test-Path -LiteralPath $certPath) -or -not (Test-Path -LiteralPath $keyPath)) {
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $name = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new('CN=localhost')
    $hash = [System.Security.Cryptography.HashAlgorithmName]::SHA256
    $padding = [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
    $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new($name, $rsa, $hash, $padding)
    $san = [System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
    $san.AddDnsName('localhost')
    $san.AddIpAddress([System.Net.IPAddress]::Parse('127.0.0.1'))
    $request.CertificateExtensions.Add($san.Build())
    $notBefore = [System.DateTimeOffset]::Now.AddDays(-1)
    $notAfter = [System.DateTimeOffset]::Now.AddYears(3)
    $cert = $request.CreateSelfSigned($notBefore, $notAfter)
    [System.IO.File]::WriteAllText($certPath, $cert.ExportCertificatePem())
    [System.IO.File]::WriteAllText($keyPath, $rsa.ExportPkcs8PrivateKeyPem())
}

$authFile = Join-Path $AuthRoot 'auth.db'
$baseHost = [string]$config.host
$scheme = [string]$config.scheme
foreach ($instance in $config.instances) {
    $name = [string]$instance.name
    $port = [int]$instance.port
    New-Item -ItemType Directory -Force -Path (Join-Path $CacheRoot $name) | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $AttachRoot $name) | Out-Null
    $serverConfig = @(
        "base-url: `"$scheme`://$baseHost`:$port`"",
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

if (-not (Test-Path -LiteralPath $authFile)) {
    New-Item -ItemType File -Force -Path $authFile | Out-Null
    $password = [Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
    $credentialPath = Join-Path $AuthRoot 'operator-credentials.txt'
    Set-Content -Path $credentialPath -Encoding ascii -Value @(
        "user=$($config.defaultUser)",
        "password=$password"
    )
    $env:NTFY_PASSWORD = $password
    & $ntfyExe user --config (Get-InstanceConfigPath 'main') add ([string]$config.defaultUser) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create ntfy user' }
    Remove-Item Env:\NTFY_PASSWORD -ErrorAction SilentlyContinue
}

foreach ($instance in $config.instances) {
    $topic = [string]$instance.topic
    & $ntfyExe access --config (Get-InstanceConfigPath 'main') ([string]$config.defaultUser) $topic read-write |
        Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to grant user access to $topic" }
    & $ntfyExe access --config (Get-InstanceConfigPath 'main') everyone $topic ([string]$config.anonymousPermission) |
        Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to grant anonymous access to $topic" }
}

& $ntfyExe help | Select-Object -First 1 | Out-Null
Write-Output "Bootstrapped ntfy $version in $RuntimeRoot"
