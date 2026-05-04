$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Stop-NtfyRepoProcesses
Write-Output 'Stopped Whispergate ntfy local instances.'
