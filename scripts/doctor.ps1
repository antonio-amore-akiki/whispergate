param(
    [switch]$Json,
    [switch]$NoExitCode
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'common.ps1')

$checks = @()
$fixes = @()
$topics = @()
$exposure = [ordered]@{ mode = 'unknown'; funnel = $false; serveConfigured = $false; target = '' }
$service = [ordered]@{ name = ''; status = 'unknown'; startType = 'unknown' }
$config = $null
$baseUrl = ''

function Add-Fix {
    param([string]$Fix)
    if ($Fix -and ($script:fixes -notcontains $Fix)) {
        $script:fixes += $Fix
    }
}

function Add-Check {
    param([string]$Name, [string]$Status, [string]$Detail, [string]$Fix)
    $script:checks += [pscustomobject]@{
        name = $Name
        status = $Status
        detail = $Detail
        fix = $Fix
    }
    if ($Status -ne 'pass') {
        Add-Fix $Fix
    }
}

try {
    $config = Get-NtfyConfig
    Add-Check 'config' 'pass' 'config.json loaded and validated.' ''
} catch {
    Add-Check 'config' 'fail' $_.Exception.Message 'Copy config.example.json to config.json and edit it.'
}

try {
    $tailscaleExe = Get-TailscaleExePath
    & $tailscaleExe status --self | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Add-Check 'tailscale' 'pass' 'tailscale status --self succeeded.' ''
    } else {
        Add-Check 'tailscale' 'fail' 'tailscale status --self failed.' 'Run tailscale up.'
    }
} catch {
    Add-Check 'tailscale' 'fail' $_.Exception.Message 'Install Tailscale and sign in.'
}

try {
    $serveText = Get-TailscaleServeText
    $target = Get-NtfyServeTarget
    $exposure.target = $target
    $exposure.funnel = $serveText -match 'Funnel on|\(Funnel on\)'
    $exposure.serveConfigured = $serveText -match [regex]::Escape($target)
    if ($exposure.funnel) {
        $exposure.mode = 'funnel'
    } elseif ($exposure.serveConfigured) {
        $exposure.mode = 'tailnet'
    }
    if ($exposure.funnel) {
        Add-Check 'exposure' 'warn' 'Tailscale Funnel is enabled.' '.\scripts\disable-funnel.ps1'
    } elseif ($exposure.serveConfigured) {
        Add-Check 'exposure' 'pass' 'Tailscale Serve is tailnet-only for ntfy.' ''
    } else {
        Add-Check 'exposure' 'fail' 'Tailscale Serve is not configured for ntfy.' '.\scripts\enable-tailnet-only.ps1'
    }
} catch {
    Add-Check 'exposure' 'fail' $_.Exception.Message '.\scripts\enable-tailnet-only.ps1'
}

try {
    $port = Get-NtfyListenPort
    $listener = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($listener) {
        Add-Check 'port' 'pass' "Port $port is listening." ''
    } else {
        Add-Check 'port' 'fail' "Port $port is not listening." '.\scripts\start.ps1'
    }
} catch {
    Add-Check 'port' 'fail' $_.Exception.Message '.\scripts\start.ps1'
}

if ($config) {
    try {
        $server = Get-NtfyServers | Select-Object -First 1
        $service.name = Get-NtfyServiceName ([string]$server.Name)
        $serviceRow = Get-Service -Name $service.name -ErrorAction SilentlyContinue
        if ($serviceRow) {
            $service.status = [string]$serviceRow.Status
            $service.startType = [string]$serviceRow.StartType
            if ($serviceRow.Status -eq 'Running') {
                Add-Check 'service' 'pass' "$($service.name) is running." ''
            } else {
                Add-Check 'service' 'fail' "$($service.name) is $($serviceRow.Status)." '.\scripts\restart-service.ps1'
            }
        } else {
            Add-Check 'service' 'warn' "$($service.name) is not installed." '.\scripts\install-service.ps1'
        }
    } catch {
        Add-Check 'service' 'fail' $_.Exception.Message '.\scripts\install-service.ps1'
    }

    try {
        $configPath = Get-PrimaryServerConfigPath
        if (Test-Path -LiteralPath $configPath) {
            $serverConfig = Get-Content -LiteralPath $configPath -Raw
            if ($serverConfig -match 'listen-https:\s*":8091"') {
                Add-Check 'generatedConfig' 'pass' 'Generated ntfy config uses HTTPS on 8091.' ''
            } else {
                Add-Check 'generatedConfig' 'fail' 'Missing listen-https :8091.' '.\scripts\bootstrap.ps1'
            }
        } else {
            Add-Check 'generatedConfig' 'fail' 'Generated ntfy config is missing.' '.\scripts\bootstrap.ps1'
        }
    } catch {
        Add-Check 'generatedConfig' 'fail' $_.Exception.Message '.\scripts\bootstrap.ps1'
    }

    if (Test-Path -LiteralPath (Get-NtfyCredentialPath)) {
        Add-Check 'credentials' 'pass' 'Operator credentials file exists.' ''
    } else {
        Add-Check 'credentials' 'fail' 'Operator credentials file is missing.' '.\scripts\bootstrap.ps1'
    }

    try {
        $healthUrl = Get-NtfyHealthUrl
        $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec $HttpTimeoutSeconds
        if ([bool]$health.healthy) {
            Add-Check 'health' 'pass' "$healthUrl is healthy." ''
        } else {
            Add-Check 'health' 'fail' "$healthUrl returned unhealthy." '.\scripts\restart-service.ps1'
        }
    } catch {
        Add-Check 'health' 'fail' $_.Exception.Message '.\scripts\restart-service.ps1'
    }

    foreach ($instance in $config.instances) {
        $topic = [string]$instance.topic
        $valid = $topic -match '^[A-Za-z0-9_-]{1,64}$'
        $topicStatus = if ($valid) { 'pass' } else { 'fail' }
        $topics += [pscustomobject]@{ topic = $topic; status = $topicStatus; detail = 'name validation' }
        if (-not $valid) {
            Add-Fix 'Use topic names with letters, numbers, underscore, or hyphen only.'
        }
    }
}

$hasFail = [bool]($checks | Where-Object { $_.status -eq 'fail' })
$hasWarn = [bool]($checks | Where-Object { $_.status -eq 'warn' })
$status = if ($hasFail) { 'fail' } elseif ($hasWarn) { 'warn' } else { 'pass' }
$result = [ordered]@{
    status = $status
    checks = $checks
    exposure = $exposure
    service = $service
    topics = $topics
    fixes = $fixes
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
} else {
    Write-Output "Whispergate doctor status: $status"
    $checks | Format-Table name, status, detail -AutoSize
    if ($topics.Count -gt 0) { $topics | Format-Table topic, status, detail -AutoSize }
    if ($fixes.Count -gt 0) {
        Write-Output 'Fixes:'
        $fixes | ForEach-Object { Write-Output "- $_" }
    }
}

if (-not $NoExitCode -and $status -eq 'fail') { exit 1 }
