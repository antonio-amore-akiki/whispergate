$ErrorActionPreference = 'Stop'

$target = Join-Path $PSScriptRoot 'setup-windows-beginner.ps1'
if (-not (Test-Path -LiteralPath $target)) {
    throw "Missing guided setup script: $target"
}

Start-Process `
    -FilePath 'powershell.exe' `
    -Verb RunAs `
    -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', $target)
