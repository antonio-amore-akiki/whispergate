param(
    [string]$OutputRoot = '',
    [string]$Configuration = 'Release',
    [string]$DotNetExe = 'dotnet'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if (-not $OutputRoot) {
    $OutputRoot = Join-Path $RepoRoot 'artifacts/release'
}

$dotnetCommand = Get-Command $DotNetExe -ErrorAction SilentlyContinue
if (-not $dotnetCommand) {
    $repoDotNet = Join-Path $RepoRoot 'runtime/dotnet/dotnet.exe'
    if (Test-Path -LiteralPath $repoDotNet) {
        $dotnetCommand = Get-Command $repoDotNet
    } else {
        throw 'dotnet SDK is required to build WhispergateSetup.exe.'
    }
}

$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
$sdkList = & $dotnetCommand.Source --list-sdks
if ($LASTEXITCODE -ne 0 -or -not $sdkList) {
    $repoDotNet = Join-Path $RepoRoot 'runtime/dotnet/dotnet.exe'
    if (-not (Test-Path -LiteralPath $repoDotNet)) {
        throw 'dotnet SDK is required. Install .NET 8 SDK or use the GitHub Actions release build.'
    }

    $dotnetCommand = Get-Command $repoDotNet
    $sdkList = & $dotnetCommand.Source --list-sdks
    if ($LASTEXITCODE -ne 0 -or -not $sdkList) {
        throw 'dotnet SDK is required. Install .NET 8 SDK or use the GitHub Actions release build.'
    }
}

$projectPath = Join-Path $RepoRoot 'installer/Whispergate.Setup/Whispergate.Setup.csproj'
if (-not (Test-Path -LiteralPath $projectPath)) {
    throw "Missing setup project: $projectPath"
}

& (Join-Path $PSScriptRoot 'check-public-safety.ps1')
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$publishRoot = Join-Path $OutputRoot 'setup-exe'
if (Test-Path -LiteralPath $publishRoot) {
    Remove-Item -LiteralPath $publishRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $publishRoot | Out-Null

& $dotnetCommand.Source publish $projectPath `
    --configuration $Configuration `
    --runtime win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:EnableCompressionInSingleFile=true `
    -o $publishRoot
if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed.' }

$builtExe = Join-Path $publishRoot 'WhispergateSetup.exe'
if (-not (Test-Path -LiteralPath $builtExe)) {
    throw 'WhispergateSetup.exe was not produced.'
}

$commit = (& git -C $RepoRoot rev-parse --short HEAD).Trim()
$releaseExe = Join-Path $OutputRoot "WhispergateSetup-$commit.exe"
Copy-Item -LiteralPath $builtExe -Destination $releaseExe -Force
$hash = Get-NtfyFileSha256 -Path $releaseExe
$checksumPath = "$releaseExe.sha256"
Set-Content -LiteralPath $checksumPath -Encoding ascii -Value "$hash  $(Split-Path -Leaf $releaseExe)"
Write-Output "Setup EXE: $releaseExe"
Write-Output "Checksum: $checksumPath"
