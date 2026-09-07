# AI Spend Tracker host — Windows, zero billable refreshes, low CPU
# Serves static UI + cache/spend.json. Does NOT call paid APIs.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Port = if ($env:SPEND_TRACKER_PORT) { [int]$env:SPEND_TRACKER_PORT } else { 8787 }
$Cache = Join-Path $Root 'cache\spend.json'
$Static = Join-Path $Root 'static'

# Optional: background refresh Grok Bot usage via free DashboardService RPCs (throttled)
$GrokRefreshScript = Join-Path $Root 'grok_usage_refresh.ps1'
$GrokCollectorScript = Join-Path $Root 'collectors\grok_bot_dashboard_rpc.ps1'
$GrokRefreshEveryMin = 30
$script:LastGrokRefresh = [datetime]::MinValue
function Maybe-RefreshGrokUsage {
  if (-not (Test-Path -LiteralPath $GrokRefreshScript)) { return }
  $elapsed = ((Get-Date) - $script:LastGrokRefresh).TotalMinutes
  if ($elapsed -lt $GrokRefreshEveryMin) { return }
  $script:LastGrokRefresh = Get-Date
  try {
    Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File', $GrokRefreshScript) -WindowStyle Hidden -Wait:$false | Out-Null
  } catch { }
}

$listener = New-Object System.Net.HttpListener
# Prefer localhost always. Add LAN IPs when Windows URL ACL allows (needed for phone PWA).
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$lanIps = @()
try {
  $lanIps = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -ExpandProperty IPAddress -Unique)
} catch {}
foreach ($ip in $lanIps) {
  try { $listener.Prefixes.Add(("http://{0}:{1}/" -f $ip, $Port)) } catch {}
}
try {
  $listener.Start()
} catch {
  # Without admin URL ACL, LAN prefixes often fail — fall back to localhost only.
  $listener = New-Object System.Net.HttpListener
  $listener.Prefixes.Add("http://127.0.0.1:$Port/")
  $listener.Start()
  $lanIps = @()
  Write-Host "LAN bind unavailable (needs one-time admin URL ACL). Localhost only."
}
Write-Host ("AI Spend Tracker on http://127.0.0.1:{0}/" -f $Port)
foreach ($ip in $lanIps) { Write-Host ("  phone/LAN: http://{0}:{1}/" -f $ip, $Port) }
Write-Host "Zero billable refreshes. Host runs hidden via START.bat / start_hidden.vbs."

function Get-Mime([string]$path) {
  $ext = [IO.Path]::GetExtension($path).ToLower()
  switch ($ext) {
    '.html' { return 'text/html; charset=utf-8' }
    '.js'   { return 'application/javascript; charset=utf-8' }
    '.css'  { return 'text/css; charset=utf-8' }
    '.json' { return 'application/json; charset=utf-8' }
    '.webmanifest' { return 'application/manifest+json; charset=utf-8' }
    '.png'  { return 'image/png' }
    '.svg'  { return 'image/svg+xml; charset=utf-8' }
    default { return 'application/octet-stream' }
  }
}

function Send-Bytes($ctx, [byte[]]$bytes, [string]$ctype, [int]$code = 200) {
  $ctx.Response.StatusCode = $code
  $ctx.Response.ContentType = $ctype
  $ctx.Response.Headers['Cache-Control'] = 'no-store'
  $ctx.Response.ContentLength64 = $bytes.Length
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $ctx.Response.Close()
}

function Send-Text($ctx, [string]$text, [string]$ctype, [int]$code = 200) {
  $bytes = [Text.Encoding]::UTF8.GetBytes($text)
  Send-Bytes $ctx $bytes $ctype $code
}

function Send-File($ctx, [string]$path) {
  if (-not (Test-Path -LiteralPath $path)) {
    Send-Text $ctx 'not found' 'text/plain' 404
    return
  }
  $bytes = [IO.File]::ReadAllBytes($path)
  Send-Bytes $ctx $bytes (Get-Mime $path)
}

function Get-PtStamp {
  try {
    $tz = [TimeZoneInfo]::FindSystemTimeZoneById('Pacific Standard Time')
  } catch {
    try { $tz = [TimeZoneInfo]::FindSystemTimeZoneById('America/Los_Angeles') } catch { $tz = $null }
  }
  $utc = [DateTimeOffset]::UtcNow
  if ($tz) {
    $local = [TimeZoneInfo]::ConvertTime($utc, $tz)
  } else {
    $local = $utc.ToOffset([TimeSpan]::FromHours(-7))
  }
  return @{
    updated_at = $utc.ToString('o')
    updated_at_pt = ($local.ToString('yyyy-MM-dd hh:mm:ss tt') + ' PT')
  }
}

function Ensure-SpendTimestamps {
  if (-not (Test-Path -LiteralPath $Cache)) { return }
  try {
    $raw = [IO.File]::ReadAllText($Cache)
    $obj = $raw | ConvertFrom-Json
    $changed = $false
    $stamp = Get-PtStamp
    if (-not $obj.updated_at) {
      $obj | Add-Member -NotePropertyName updated_at -NotePropertyValue $stamp.updated_at -Force
      $changed = $true
    }
    if (-not $obj.updated_at_pt) {
      $obj | Add-Member -NotePropertyName updated_at_pt -NotePropertyValue $stamp.updated_at_pt -Force
      $changed = $true
    }
    if (-not $obj.meta) {
      $obj | Add-Member -NotePropertyName meta -NotePropertyValue ([pscustomobject]@{}) -Force
      $changed = $true
    }
    if ($obj.meta -and -not $obj.meta.updated_at) {
      $obj.meta | Add-Member -NotePropertyName updated_at -NotePropertyValue $obj.updated_at -Force
      $changed = $true
    }
    if ($obj.meta -and -not $obj.meta.updated_at_pt) {
      $obj.meta | Add-Member -NotePropertyName updated_at_pt -NotePropertyValue $obj.updated_at_pt -Force
      $changed = $true
    }
    if ($changed) {
      $json = $obj | ConvertTo-Json -Depth 20
      [IO.File]::WriteAllText($Cache, $json)
    }
  } catch { }
}

function Read-SpendObject {
  if (-not (Test-Path -LiteralPath $Cache)) {
    return [pscustomobject]@{ rows = @(); updated_at = $null; updated_at_pt = $null; meta = [pscustomobject]@{} }
  }
  try {
    $raw = [IO.File]::ReadAllText($Cache)
    return ($raw | ConvertFrom-Json)
  } catch {
    return [pscustomobject]@{ rows = @(); updated_at = $null; updated_at_pt = $null; meta = [pscustomobject]@{}; parse_error = $_.Exception.Message }
  }
}

function Send-Spend($ctx) {
  # Fast path: return cache JSON only — never billable network
  if (-not (Test-Path -LiteralPath $Cache)) {
    Send-Text $ctx '{"rows":[],"updated_at":null,"updated_at_pt":null}' 'application/json; charset=utf-8'
    return
  }
  Send-File $ctx $Cache
}

function Invoke-LocalRefresh {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $sources = New-Object System.Collections.Generic.List[string]
  $ok = $true
  $err = $null

  $scriptToRun = $null
  $argList = $null
  if (Test-Path -LiteralPath $GrokRefreshScript) {
    $scriptToRun = $GrokRefreshScript
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $GrokRefreshScript, '-Force')
    [void]$sources.Add('grok_usage_refresh.ps1')
  } elseif (Test-Path -LiteralPath $GrokCollectorScript) {
    $scriptToRun = $GrokCollectorScript
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $GrokCollectorScript, '-Force')
    [void]$sources.Add('collectors/grok_bot_dashboard_rpc.ps1')
  } else {
    $ok = $false
    $err = 'No local grok refresh script found'
  }

  if ($scriptToRun) {
    try {
      # Synchronous wait up to ~25s so response includes fresh cache
      $proc = Start-Process -FilePath powershell.exe -ArgumentList $argList -WindowStyle Hidden -PassThru -Wait:$false
      $finished = $proc.WaitForExit(25000)
      if (-not $finished) {
        try { $proc.Kill() } catch { }
        $ok = $false
        $err = 'Grok refresh timed out after 25s'
      } elseif ($proc.ExitCode -ne 0 -and $null -ne $proc.ExitCode) {
        # Collector may exit 0 even on soft skip; non-zero is a soft warning
        if (-not $err) { $err = "Refresh exit code $($proc.ExitCode)" }
        # Still treat as ok if spend.json exists — local cache may be updated
        if (Test-Path -LiteralPath $Cache) { $ok = $true }
      }
      $script:LastGrokRefresh = Get-Date
    } catch {
      $ok = $false
      $err = $_.Exception.Message
    }
  }

  Ensure-SpendTimestamps
  $sw.Stop()

  return @{
    ok = $ok
    sources = @($sources)
    duration_ms = [int]$sw.ElapsedMilliseconds
    error = $err
  }
}

function Send-SpendRefresh($ctx) {
  $refresh = Invoke-LocalRefresh
  $spend = Read-SpendObject

  # Build response: rows + meta + refresh envelope
  $payload = [ordered]@{}
  if ($spend.PSObject.Properties['rows']) { $payload['rows'] = $spend.rows } else { $payload['rows'] = @() }
  if ($spend.PSObject.Properties['updated_at']) { $payload['updated_at'] = $spend.updated_at }
  if ($spend.PSObject.Properties['updated_at_pt']) { $payload['updated_at_pt'] = $spend.updated_at_pt }
  if ($spend.PSObject.Properties['meta']) { $payload['meta'] = $spend.meta } else { $payload['meta'] = [pscustomobject]@{} }
  $refreshObj = [ordered]@{
    ok = [bool]$refresh.ok
    sources = @($refresh.sources)
    duration_ms = [int]$refresh.duration_ms
  }
  if ($refresh.error) { $refreshObj['error'] = [string]$refresh.error }
  $payload['refresh'] = [pscustomobject]$refreshObj

  $json = ($payload | ConvertTo-Json -Depth 20 -Compress)
  Send-Text $ctx $json 'application/json; charset=utf-8'
}

try {
  while ($listener.IsListening) {
    Maybe-RefreshGrokUsage
    $ctx = $listener.GetContext()
    $path = $ctx.Request.Url.AbsolutePath.TrimEnd('/')
    $method = $ctx.Request.HttpMethod.ToUpperInvariant()
    if ([string]::IsNullOrEmpty($path) -or $path -eq '/') {
      Send-File $ctx (Join-Path $Static 'index.html')
      continue
    }
    if ($path -eq '/api/health') {
      Send-Text $ctx '{"ok":true,"service":"spend-tracker","port":8787}' 'application/json; charset=utf-8'
      continue
    }
    if ($path -eq '/api/spend') {
      # Cache only — fast, no collectors
      Send-Spend $ctx
      continue
    }
    if ($path -eq '/api/spend/refresh') {
      # Manual refresh: run local collectors (never billable APIs), then return spend.json + refresh meta
      if ($method -eq 'GET' -or $method -eq 'POST') {
        Send-SpendRefresh $ctx
      } else {
        Send-Text $ctx '{"error":"method not allowed"}' 'application/json; charset=utf-8' 405
      }
      continue
    }
    if ($path -eq '/manifest.webmanifest') {
      Send-File $ctx (Join-Path $Static 'manifest.webmanifest')
      continue
    }
    if ($path -eq '/sw.js') {
      $swPath = Join-Path $Static 'sw.js'
      if (-not (Test-Path -LiteralPath $swPath)) { Send-Text $ctx 'not found' 'text/plain' 404; continue }
      $bytes = [IO.File]::ReadAllBytes($swPath)
      $ctx.Response.StatusCode = 200
      $ctx.Response.ContentType = 'application/javascript; charset=utf-8'
      $ctx.Response.Headers['Cache-Control'] = 'no-cache'
      $ctx.Response.ContentLength64 = $bytes.Length
      $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
      $ctx.Response.Close()
      continue
    }
    $name = $path.TrimStart('/')
    # icons under static/icons
    $candidate = Join-Path $Static $name
    if (Test-Path -LiteralPath $candidate) {
      Send-File $ctx $candidate
      continue
    }
    Send-Text $ctx 'not found' 'text/plain' 404
  }
} finally {
  if ($listener.IsListening) { $listener.Stop() }
  $listener.Close()
}
