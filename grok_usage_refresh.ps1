# Optional refresh hook for Grok Bot DashboardService usage (free, read-only).
# Called from START.bat; throttled inside collector to >= 15 minutes unless -Force.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Collector = Join-Path $Root 'collectors\grok_bot_dashboard_rpc.ps1'
if (-not (Test-Path -LiteralPath $Collector)) {
  Write-Host "Collector missing: $Collector"
  exit 0
}
$argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $Collector)
if ($args -contains '-Force') { $argList += '-Force' }
try {
  & powershell @argList
} catch {
  Write-Host "grok_usage_refresh warning: $($_.Exception.Message)"
  exit 0
}
