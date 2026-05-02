$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$config = Get-NtfyConfig
$baseHost = [string]$config.host
Assert-TailscaleReady -HostName $baseHost
$rows = @()
$blockedTopic = 'blocked-topic-proof'

foreach ($instance in $config.instances) {
    $name = [string]$instance.name
    $port = [int]$instance.port
    $topic = [string]$instance.topic
    $healthUrl = "https://$baseHost`:$port/v1/health"
    $publishUrl = "https://$baseHost`:$port/$topic"
    $blockedUrl = "https://$baseHost`:$port/$blockedTopic"
    $httpUrl = "http://$baseHost`:$port/v1/health"
    $tailscaleHealthy = $false
    $publishHealthy = $false
    $unknownDenied = $false
    $httpRejected = $false
    $errorText = ''

    try {
        $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec $HttpTimeoutSeconds
        $tailscaleHealthy = [bool]$health.healthy
    }
    catch {
        $errorText = $_.Exception.Message
    }

    try {
        $publish = Invoke-RestMethod -Method Post `
            -Uri $publishUrl `
            -TimeoutSec $HttpTimeoutSeconds `
            -Body "verify $(Get-Date -Format HHmmss)"
        $publishHealthy = [bool]$publish.id
    }
    catch {
        $errorText = "$errorText publish=$($_.Exception.Message)".Trim()
    }

    try {
        Invoke-RestMethod -Method Post `
            -Uri $blockedUrl `
            -TimeoutSec $HttpTimeoutSeconds `
            -Body 'blocked proof' | Out-Null
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 403) {
            $unknownDenied = $true
        } else {
            $errorText = "$errorText blocked=$($_.Exception.Message)".Trim()
        }
    }

    try {
        $httpResponse = Invoke-WebRequest -Uri $httpUrl -TimeoutSec $HttpTimeoutSeconds
        if ($httpResponse.StatusCode -ne 200) {
            $httpRejected = $true
        }
    }
    catch {
        $httpRejected = $true
    }

    $rows += [pscustomobject]@{
        Instance = $name
        Host = $baseHost
        Port = $port
        TailscaleHealthy = $tailscaleHealthy
        PublishHealthy = $publishHealthy
        UnknownDenied = $unknownDenied
        HttpRejected = $httpRejected
        Error = $errorText
    }
}

$rows | Format-Table -AutoSize

$failed = $rows | Where-Object {
    -not $_.TailscaleHealthy -or
    -not $_.PublishHealthy -or
    -not $_.UnknownDenied -or
    -not $_.HttpRejected
}
if ($failed.Count -gt 0) {
    exit 1
}
