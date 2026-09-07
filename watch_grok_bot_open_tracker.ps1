# Watch for a new Grok Bot desktop session; open AI Spend Tracker dialog ONCE per launch.
# Owned by Hatch. Low CPU: sleep 5s. Zero billable network beyond local host.
$ErrorActionPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Stamp = Join-Path $Root 'cache\last_grok_bot_open_session.txt'
$OpenScript = Join-Path $Root 'open_app_window.ps1'
$ServeScript = Join-Path $Root 'serve.ps1'
$Log = Join-Path $Root 'cache\grok_bot_open_watcher.log'

New-Item -ItemType Directory -Force -Path (Join-Path $Root 'cache') | Out-Null

function Write-Log([string]$msg) {
  $line = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  Add-Content -LiteralPath $Log -Value $line -Encoding UTF8
}

function Ensure-Host {
  try {
    $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8787/api/health' -UseBasicParsing -TimeoutSec 2
    if ($r.StatusCode -eq 200) { return $true }
  } catch {}
  Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File', $ServeScript) -WindowStyle Minimized | Out-Null
  Start-Sleep -Seconds 2
  try {
    $r2 = Invoke-WebRequest -Uri 'http://127.0.0.1:8787/api/health' -UseBasicParsing -TimeoutSec 3
    return ($r2.StatusCode -eq 200)
  } catch { return $false }
}

function Get-GrokSessionKey {
  $procs = @(Get-Process -Name 'Grok Bot' -ErrorAction SilentlyContinue | Sort-Object StartTime)
  if (-not $procs -or $procs.Count -eq 0) { return $null }
  $first = $procs[0]
  return ('{0}|{1}' -f $first.StartTime.ToUniversalTime().ToString('o'), $first.Id)
}

function Open-OnceForSession([string]$sessionKey) {
  $last = $null
  if (Test-Path -LiteralPath $Stamp) { $last = (Get-Content -LiteralPath $Stamp -Raw).Trim() }
  if ($last -eq $sessionKey) { return $false }
  if (-not (Ensure-Host)) {
    Write-Log 'host failed; skip open'
    return $false
  }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $OpenScript | Out-Null
  Set-Content -LiteralPath $Stamp -Value $sessionKey -Encoding UTF8
  Write-Log ("opened for session " + $sessionKey)
  return $true
}

Write-Log 'watcher start'
while ($true) {
  $key = Get-GrokSessionKey
  if ($key) {
    [void](Open-OnceForSession $key)
  }
  Start-Sleep -Seconds 5
}
