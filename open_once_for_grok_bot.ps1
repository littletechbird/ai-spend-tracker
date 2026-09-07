# One-shot: if Grok Bot is running and this session not yet opened, open the tracker dialog.
# Also usable by Hatch: powershell -File open_once_for_grok_bot.ps1 -Force
param([switch]$Force)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Stamp = Join-Path $Root 'cache\last_grok_bot_open_session.txt'
$OpenScript = Join-Path $Root 'open_app_window.ps1'
$ServeScript = Join-Path $Root 'serve.ps1'

function Ensure-Host {
  try {
    $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8787/api/health' -UseBasicParsing -TimeoutSec 2
    if ($r.StatusCode -eq 200) { return }
  } catch {}
  Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File', $ServeScript) -WindowStyle Minimized | Out-Null
  Start-Sleep -Seconds 2
}

$procs = @(Get-Process -Name 'Grok Bot' -ErrorAction SilentlyContinue | Sort-Object StartTime)
if (-not $procs -or $procs.Count -eq 0) {
  if (-not $Force) { Write-Host 'Grok Bot not running; skip'; exit 0 }
  $sessionKey = 'manual-force|' + (Get-Date).ToUniversalTime().ToString('o')
} else {
  $first = $procs[0]
  $sessionKey = '{0}|{1}' -f $first.StartTime.ToUniversalTime().ToString('o'), $first.Id
}

$last = $null
if (Test-Path -LiteralPath $Stamp) { $last = (Get-Content -LiteralPath $Stamp -Raw).Trim() }
if ((-not $Force) -and ($last -eq $sessionKey)) {
  Write-Host 'Already opened for this Grok Bot session'
  exit 0
}

Ensure-Host
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $OpenScript
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'cache') | Out-Null
Set-Content -LiteralPath $Stamp -Value $sessionKey -Encoding UTF8
Write-Host ('Opened for session ' + $sessionKey)
