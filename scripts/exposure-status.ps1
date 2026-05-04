param([switch]$Json)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$serveText = Get-TailscaleServeText
$target = Get-NtfyServeTarget
$funnel = $serveText -match 'Funnel on|\(Funnel on\)'
$serveConfigured = $serveText -match [regex]::Escape($target)
$mode = if ($funnel) { 'funnel' } elseif ($serveConfigured) { 'tailnet' } else { 'missing' }
$result = [ordered]@{ mode = $mode; funnel = $funnel; serveConfigured = $serveConfigured; target = $target }
if ($Json) { $result | ConvertTo-Json -Depth 4 } else { $result; Write-Output $serveText }
