param([switch]$CheckOnly)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

function Write-Step {
    param([string]$Text)
    Write-Output ''
    Write-Output "== $Text =="
}

function Stop-WithNextAction {
    param(
        [string]$Message,
        [string]$NextAction
    )
    Write-Output ''
    Write-Output "STOP: $Message"
    Write-Output "Next: $NextAction"
    exit 1
}

function Test-AdminShell {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DetectedTailscaleHost {
    try {
        $tailscaleExe = Get-TailscaleExePath
    } catch {
        Stop-WithNextAction `
            -Message 'Tailscale is not installed.' `
            -NextAction 'Install Tailscale from https://tailscale.com/download/windows, sign in, then run START-HERE-Windows.bat again.'
    }

    $statusRaw = & $tailscaleExe status --self --json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Stop-WithNextAction `
            -Message 'Tailscale is installed but not signed in or not running.' `
            -NextAction 'Open Tailscale, sign in, wait until it says Connected, then run START-HERE-Windows.bat again.'
    }

    try {
        $status = ($statusRaw -join "`n") | ConvertFrom-Json
    } catch {
        Stop-WithNextAction `
            -Message 'Tailscale did not return readable status.' `
            -NextAction 'Open Tailscale, confirm it is connected, then run START-HERE-Windows.bat again.'
    }

    if ([string]$status.BackendState -ne 'Running') {
        Stop-WithNextAction `
            -Message "Tailscale state is $($status.BackendState), not Running." `
            -NextAction 'Open Tailscale, sign in, wait until it says Connected, then run START-HERE-Windows.bat again.'
    }
    if ($status.Self.Online -ne $true) {
        Stop-WithNextAction `
            -Message 'This computer is not online in Tailscale.' `
            -NextAction 'Open Tailscale, sign in, wait until it says Connected, then run START-HERE-Windows.bat again.'
    }

    $hostName = ([string]$status.Self.DNSName).Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($hostName) -or $hostName -notmatch '\.ts\.net$') {
        Stop-WithNextAction `
            -Message 'Tailscale MagicDNS name was not available.' `
            -NextAction 'Enable MagicDNS in the Tailscale admin console, then run START-HERE-Windows.bat again.'
    }
    return $hostName
}

function Ensure-BeginnerConfig {
    param([string]$DetectedHost)

    $configPath = Join-Path $RepoRoot 'config.json'
    $examplePath = Join-Path $RepoRoot 'config.example.json'
    if (-not (Test-Path -LiteralPath $configPath)) {
        Copy-Item -LiteralPath $examplePath -Destination $configPath
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $config.host = $DetectedHost
        $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath -Encoding ascii
        Write-Output "Created config.json with Tailscale host $DetectedHost."
        return
    }

    $existing = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $hostText = ([string]$existing.host).Trim().TrimEnd('.')
    if ($hostText -eq 'your-device.your-tailnet.ts.net') {
        $existing.host = $DetectedHost
        $existing | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath -Encoding ascii
        Write-Output "Updated config.json with Tailscale host $DetectedHost."
        return
    }

    if ($hostText -ne $DetectedHost) {
        Stop-WithNextAction `
            -Message "config.json host is $hostText, but this computer is $DetectedHost." `
            -NextAction "Open config.json, set host to $DetectedHost, save it, then run START-HERE-Windows.bat again."
    }
}

try {
    if ([string]$env:OS -ne 'Windows_NT') {
        Stop-WithNextAction `
            -Message 'This guided setup is for Windows.' `
            -NextAction 'Use the Linux beta commands in README.md on Linux.'
    }

    if (-not (Test-AdminShell)) {
        Write-Output 'Opening Administrator PowerShell. Approve the Windows prompt.'
        Start-Process `
            -FilePath 'powershell.exe' `
            -Verb RunAs `
            -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        exit 0
    }

    Set-Location -LiteralPath $RepoRoot
    Write-Output 'Whispergate guided Windows setup'

    Write-Step 'Checking Tailscale'
    $detectedHost = Get-DetectedTailscaleHost
    Write-Output "Tailscale host: $detectedHost"

    Write-Step 'Preparing config'
    Ensure-BeginnerConfig -DetectedHost $detectedHost
    Get-NtfyConfig | Out-Null

    if ($CheckOnly) {
        Write-Output 'Check-only mode passed.'
        exit 0
    }

    if (Test-Path -LiteralPath $RuntimeRoot) {
        Write-Step 'Existing install found'
        Write-Output 'The guided setup will not overwrite local runtime state.'
        & (Join-Path $PSScriptRoot 'doctor.ps1')
        & (Join-Path $PSScriptRoot 'verify.ps1')
        Write-Output ''
        Write-Output 'Already installed. If checks passed, use the phone URL below.'
        Write-Output "Phone URL: https://$detectedHost"
        Write-Output 'Do not add :8091 on the phone.'
        exit 0
    }

    Write-Step 'Installing Whispergate'
    & (Join-Path $PSScriptRoot 'setup.ps1')

    Write-Step 'Finished'
    Write-Output "Phone URL: https://$detectedHost"
    Write-Output 'Do not add :8091 on the phone.'
    Write-Output 'Operator credentials are saved under runtime\auth\operator-credentials.txt.'
    exit 0
} catch {
    Stop-WithNextAction `
        -Message $_.Exception.Message `
        -NextAction 'Fix the message above, then run START-HERE-Windows.bat again.'
}
