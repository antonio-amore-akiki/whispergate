$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$tracked = & git -C $repoRoot ls-files
if ($LASTEXITCODE -ne 0) {
    throw 'git ls-files failed.'
}

$blocked = @()
foreach ($path in $tracked) {
    $normalized = $path.Replace('\', '/')
    if ($normalized -eq 'config.json' -or
        $normalized -like 'runtime/*' -or
        $normalized -like '.planning/*' -or
        $normalized -like '*.db' -or
        $normalized -like '*.log' -or
        $normalized -like '*.key' -or
        $normalized -like '*.crt' -or
        $normalized -like '*.pfx' -or
        $normalized -like '*.zip' -or
        $normalized -like '*operator-credentials.txt') {
        $blocked += $normalized
    }
}

if ($blocked.Count -gt 0) {
    $blocked | Sort-Object | ForEach-Object { Write-Error "Blocked tracked private file: $_" }
    throw 'Public-source secret scan failed.'
}

$parseFailed = $false
$scriptFiles = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'scripts') -Filter '*.ps1' -File
foreach ($scriptFile in $scriptFiles) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptFile.FullName,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null
    if ($errors.Count -gt 0) {
        $parseFailed = $true
        foreach ($errorItem in $errors) {
            Write-Error "$($scriptFile.Name): $($errorItem.Message)"
        }
    }
}

if ($parseFailed) {
    throw 'PowerShell parser check failed.'
}

Write-Output 'Public-source safety checks passed.'
