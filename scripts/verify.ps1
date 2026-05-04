$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$config = Get-NtfyConfig
$baseHost = [string]$config.host
$scheme = [string]$config.scheme
Assert-TailscaleReady -HostName $baseHost
$primaryServer = Get-NtfyServers | Select-Object -First 1
$primaryConfigPath = Get-InstanceConfigPath ([string]$primaryServer.Name)
$rows = @()
$blockedTopic = 'blocked-topic-proof'

function Get-OperatorAuthHeaders {
    $credentialPath = Join-Path $AuthRoot 'operator-credentials.txt'
    if (-not (Test-Path -LiteralPath $credentialPath)) {
        throw 'Missing operator credentials. Run .\scripts\bootstrap.ps1 first.'
    }
    $credentialPairs = @{}
    Get-Content -LiteralPath $credentialPath | ForEach-Object {
        $key, $value = $_.Split('=', 2)
        $credentialPairs[$key] = $value
    }
    $rawCredential = "$($credentialPairs.user):$($credentialPairs.password)"
    $encodedCredential = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($rawCredential))
    return @{ Authorization = "Basic $encodedCredential" }
}

function Convert-ResponseContentToText {
    param([object]$Content)
    if ($Content -is [byte[]]) {
        return [Text.Encoding]::UTF8.GetString($Content)
    }
    return [string]$Content
}

function Test-PublishedMessageReceived {
    param(
        [string]$ReceiveUrl,
        [string]$ExpectedId,
        [hashtable]$Headers
    )
    $receiveResponse = Invoke-WebRequest `
        -Uri $ReceiveUrl `
        -Headers $Headers `
        -TimeoutSec $HttpTimeoutSeconds
    $receiveText = Convert-ResponseContentToText -Content $receiveResponse.Content
    foreach ($line in ($receiveText -split "`n")) {
        $trimmed = $line.Trim()
        if (-not $trimmed) {
            continue
        }
        $message = $trimmed | ConvertFrom-Json
        if ([string]$message.id -eq $ExpectedId) {
            return $true
        }
    }
    return $false
}

function Test-WebSocketConnect {
    param(
        [string]$TopicUrl,
        [hashtable]$Headers
    )
    Add-Type -AssemblyName System.Net.WebSockets.Client
    Add-Type -AssemblyName System.Threading
    $webSocket = [System.Net.WebSockets.ClientWebSocket]::new()
    foreach ($entry in $Headers.GetEnumerator()) {
        $webSocket.Options.SetRequestHeader($entry.Key, [string]$entry.Value)
    }
    $socketUrl = $TopicUrl -replace '^https://', 'wss://'
    $uri = [Uri]("$socketUrl/ws")
    $cancel = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($HttpTimeoutSeconds))
    try {
        $null = $webSocket.ConnectAsync($uri, $cancel.Token).GetAwaiter().GetResult()
        return ($webSocket.State -eq [System.Net.WebSockets.WebSocketState]::Open)
    }
    finally {
        $webSocket.Dispose()
        $cancel.Dispose()
    }
}

$operatorHeaders = Get-OperatorAuthHeaders

foreach ($instance in $config.instances) {
    $name = [string]$instance.name
    $port = [int]$instance.port
    $topic = [string]$instance.topic
    $baseUrl = Get-NtfyExternalBaseUrl -Scheme $scheme -HostName $baseHost -ExternalPort $port
    Assert-NoExplicitBackendPort -Url $baseUrl
    $serverConfig = Get-Content -LiteralPath $primaryConfigPath
    $baseUrlLine = $serverConfig | Where-Object { $_ -match '^base-url:\s*"(?<url>[^"]+)"\s*$' }
    $generatedBaseUrl = [regex]::Match($baseUrlLine, '^base-url:\s*"(?<url>[^"]+)"\s*$').Groups['url'].Value
    if ($generatedBaseUrl -ne $baseUrl) {
        throw 'Generated ntfy server config must use the no-port Tailscale HTTPS URL.'
    }
    $healthUrl = "$baseUrl/v1/health"
    $publishUrl = "$baseUrl/$topic"
    $receiveUrl = "$baseUrl/$topic/json?poll=1&since=all"
    $blockedUrl = "$baseUrl/$blockedTopic"
    $httpUrl = "http://$baseHost/v1/health"
    $tailscaleHealthy = $false
    $publishHealthy = $false
    $receiveHealthy = $false
    $unknownDenied = $false
    $httpRejected = $false
    $webSocketHealthy = $false
    $errorText = ''
    $publishedId = ''

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
        $publishedId = [string]$publish.id
        $publishHealthy = [bool]$publishedId
    }
    catch {
        $errorText = "$errorText publish=$($_.Exception.Message)".Trim()
    }

    if ($publishHealthy) {
        try {
            $receiveHealthy = Test-PublishedMessageReceived `
                -ReceiveUrl $receiveUrl `
                -ExpectedId $publishedId `
                -Headers $operatorHeaders
        }
        catch {
            $errorText = "$errorText receive=$($_.Exception.Message)".Trim()
        }
    }

    try {
        $webSocketHealthy = Test-WebSocketConnect -TopicUrl $publishUrl -Headers $operatorHeaders
    }
    catch {
        $errorText = "$errorText websocket=$($_.Exception.Message)".Trim()
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
        Url = $baseUrl
        TailscaleHealthy = $tailscaleHealthy
        PublishHealthy = $publishHealthy
        ReceiveHealthy = $receiveHealthy
        WebSocketHealthy = $webSocketHealthy
        UnknownDenied = $unknownDenied
        HttpRejected = $httpRejected
        Error = $errorText
    }
}

$rows | Format-Table -AutoSize

$failed = $rows | Where-Object {
    -not $_.TailscaleHealthy -or
    -not $_.PublishHealthy -or
    -not $_.ReceiveHealthy -or
    -not $_.WebSocketHealthy -or
    -not $_.UnknownDenied -or
    -not $_.HttpRejected
}
if ($failed.Count -gt 0) {
    exit 1
}
