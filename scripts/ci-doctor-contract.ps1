$ErrorActionPreference = 'Stop'

Copy-Item .\config.example.json .\config.json
$json = .\scripts\doctor.ps1 -Json -NoExitCode
$parsed = $json | ConvertFrom-Json
if (-not $parsed.status) { throw 'doctor status missing' }
if (-not $parsed.checks) { throw 'doctor checks missing' }
if (-not $parsed.exposure) { throw 'doctor exposure missing' }
if (-not $parsed.service) { throw 'doctor service missing' }
if (-not $parsed.topics) { throw 'doctor topics missing' }
if ($null -eq $parsed.fixes) { throw 'doctor fixes missing' }
