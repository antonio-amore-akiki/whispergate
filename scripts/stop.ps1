$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Stop-NtfyRepoProcesses
Write-Output 'Stopped ntfy Marmoura local instances.'
