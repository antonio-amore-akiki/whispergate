param(
    [switch]$NoVerify
)

. (Join-Path $PSScriptRoot 'common.ps1')

$config = Get-NtfyConfig
$primaryConfigPath = Get-PrimaryServerConfigPath
$ntfyExe = Get-NtfyExePath
$userName = [string]$config.defaultUser
$targetName = Get-NtfyCredentialTarget
$oldCredential = Get-WindowsCredential -TargetName $targetName
$passwordChanged = $false
$rotationVerified = $false
$newPassword = New-NtfyRandomPassword
$legacyCredentialPath = Get-NtfyCredentialPath

try {
    Set-WindowsCredential -TargetName $targetName -UserName $userName -Password $newPassword
    $env:NTFY_PASSWORD = $newPassword
    & $ntfyExe user --config $primaryConfigPath change-pass $userName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Failed to rotate ntfy user password.' }
    $passwordChanged = $true
    Remove-Item -LiteralPath $legacyCredentialPath -Force -ErrorAction SilentlyContinue
    if (-not $NoVerify) {
        Restart-Service -Name (Get-NtfyServiceName 'main') -Force -ErrorAction Stop
        Start-Sleep -Seconds $ServiceStartupSeconds
        & (Join-Path $PSScriptRoot 'verify.ps1') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Verification failed after password rotation.' }
        $rotationVerified = $true
    } else {
        $rotationVerified = $true
    }
    [pscustomobject]@{
        ok = $true
        rotated = $true
        user = $userName
        credential_target = $targetName
        legacy_file_present = (Test-Path -LiteralPath $legacyCredentialPath)
    } | ConvertTo-Json -Compress
} catch {
    if ((-not $rotationVerified) -and $null -ne $oldCredential) {
        Set-WindowsCredential `
            -TargetName $targetName `
            -UserName ([string]$oldCredential.UserName) `
            -Password ([string]$oldCredential.Password)
        try {
            $env:NTFY_PASSWORD = [string]$oldCredential.Password
            & $ntfyExe user --config $primaryConfigPath change-pass ([string]$oldCredential.UserName) | Out-Null
        } finally {
            Remove-Item Env:\NTFY_PASSWORD -ErrorAction SilentlyContinue
        }
    }
    throw
} finally {
    Remove-Item Env:\NTFY_PASSWORD -ErrorAction SilentlyContinue
}
