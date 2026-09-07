# Grok Bot DashboardService usage collector — FREE read-only, no inference.
# Decrypts Electron safeStorage (OSCrypt v10) via DPAPI + AES-GCM, calls:
#   GetSandUsageStatus + GetCurrentPeriodUsage
# Writes cache\grok_bot_usage_live.json and merges spend.json row id=grok-cursor.
# NEVER logs raw tokens — only len/prefix fingerprints.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$CacheDir = Join-Path $Root 'cache'
$LivePath = Join-Path $CacheDir 'grok_bot_usage_live.json'
$SpendPath = Join-Path $CacheDir 'spend.json'
$MinIntervalMin = 15
$Force = $false
if ($args -contains '-Force') { $Force = $true }

# Throttle unless -Force
if (-not $Force -and (Test-Path -LiteralPath $LivePath)) {
  $prev = Get-Item -LiteralPath $LivePath
  $ageMin = ((Get-Date) - $prev.LastWriteTime).TotalMinutes
  if ($ageMin -lt $MinIntervalMin) {
    Write-Host ("Skip: live cache age {0:N1}m < {1}m (use -Force)" -f $ageMin, $MinIntervalMin)
    exit 0
  }
}

if (-not ('DpapiUtil' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class DpapiUtil {
  [DllImport("crypt32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  static extern bool CryptUnprotectData(ref DATA_BLOB pDataIn, string szDataDescr,
    IntPtr pOptionalEntropy, IntPtr pvReserved, IntPtr pPromptStruct, int dwFlags, ref DATA_BLOB pDataOut);
  [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr hMem);
  [StructLayout(LayoutKind.Sequential)]
  public struct DATA_BLOB { public int cbData; public IntPtr pbData; }
  public static byte[] Unprotect(byte[] data) {
    DATA_BLOB input = new DATA_BLOB();
    DATA_BLOB output = new DATA_BLOB();
    input.cbData = data.Length;
    input.pbData = Marshal.AllocHGlobal(data.Length);
    try {
      Marshal.Copy(data, 0, input.pbData, data.Length);
      if (!CryptUnprotectData(ref input, null, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 0, ref output))
        throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
      byte[] res = new byte[output.cbData];
      Marshal.Copy(output.pbData, res, 0, output.cbData);
      return res;
    } finally {
      if (input.pbData != IntPtr.Zero) Marshal.FreeHGlobal(input.pbData);
      if (output.pbData != IntPtr.Zero) LocalFree(output.pbData);
    }
  }
}

public static class AesGcmBCrypt {
  [DllImport("bcrypt.dll")] static extern uint BCryptOpenAlgorithmProvider(out IntPtr phAlgorithm, [MarshalAs(UnmanagedType.LPWStr)] string pszAlgId, [MarshalAs(UnmanagedType.LPWStr)] string pszImplementation, uint dwFlags);
  [DllImport("bcrypt.dll")] static extern uint BCryptSetProperty(IntPtr hObject, [MarshalAs(UnmanagedType.LPWStr)] string pszProperty, byte[] pbInput, int cbInput, uint dwFlags);
  [DllImport("bcrypt.dll")] static extern uint BCryptGenerateSymmetricKey(IntPtr hAlgorithm, out IntPtr phKey, IntPtr pbKeyObject, int cbKeyObject, byte[] pbSecret, int cbSecret, uint dwFlags);
  [DllImport("bcrypt.dll")] static extern uint BCryptDecrypt(IntPtr hKey, byte[] pbInput, int cbInput, ref BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO pPaddingInfo, byte[] pbIV, int cbIV, byte[] pbOutput, int cbOutput, out int pcbResult, uint dwFlags);
  [DllImport("bcrypt.dll")] static extern uint BCryptDestroyKey(IntPtr hKey);
  [DllImport("bcrypt.dll")] static extern uint BCryptCloseAlgorithmProvider(IntPtr hAlgorithm, uint dwFlags);
  [StructLayout(LayoutKind.Sequential)]
  public struct BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO {
    public int cbSize; public int dwInfoVersion;
    public IntPtr pbNonce; public int cbNonce;
    public IntPtr pbAuthData; public int cbAuthData;
    public IntPtr pbTag; public int cbTag;
    public IntPtr pbMacContext; public int cbMacContext;
    public int cbAAD; public long cbData; public int dwFlags;
  }
  public static byte[] Decrypt(byte[] key, byte[] nonce, byte[] ciphertext, byte[] tag) {
    IntPtr hAlg, hKey;
    uint st = BCryptOpenAlgorithmProvider(out hAlg, "AES", null, 0);
    if (st != 0) throw new Exception("BCryptOpenAlgorithmProvider "+st);
    try {
      byte[] chain = Encoding.Unicode.GetBytes("ChainingModeGCM\0");
      st = BCryptSetProperty(hAlg, "ChainingMode", chain, chain.Length, 0);
      if (st != 0) throw new Exception("BCryptSetProperty "+st);
      st = BCryptGenerateSymmetricKey(hAlg, out hKey, IntPtr.Zero, 0, key, key.Length, 0);
      if (st != 0) throw new Exception("BCryptGenerateSymmetricKey "+st);
      try {
        var info = new BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO();
        info.cbSize = Marshal.SizeOf(typeof(BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO));
        info.dwInfoVersion = 1;
        info.pbNonce = Marshal.AllocHGlobal(nonce.Length); info.cbNonce = nonce.Length;
        Marshal.Copy(nonce, 0, info.pbNonce, nonce.Length);
        info.pbTag = Marshal.AllocHGlobal(tag.Length); info.cbTag = tag.Length;
        Marshal.Copy(tag, 0, info.pbTag, tag.Length);
        try {
          byte[] output = new byte[ciphertext.Length];
          int result;
          st = BCryptDecrypt(hKey, ciphertext, ciphertext.Length, ref info, null, 0, output, output.Length, out result, 0);
          if (st != 0) throw new Exception("BCryptDecrypt 0x"+st.ToString("X"));
          if (result != output.Length) { byte[] trimmed = new byte[result]; Buffer.BlockCopy(output,0,trimmed,0,result); return trimmed; }
          return output;
        } finally {
          Marshal.FreeHGlobal(info.pbNonce); Marshal.FreeHGlobal(info.pbTag);
        }
      } finally { BCryptDestroyKey(hKey); }
    } finally { BCryptCloseAlgorithmProvider(hAlg, 0); }
  }
}
"@
}

function Get-OsCryptKey {
  $ls = Get-Content (Join-Path $env:APPDATA 'Grok Bot\Local State') -Raw | ConvertFrom-Json
  $enc = [Convert]::FromBase64String($ls.os_crypt.encrypted_key)
  if ([Text.Encoding]::ASCII.GetString($enc,0,5) -ne 'DPAPI') { throw 'Local State key not DPAPI' }
  $blob = New-Object byte[] ($enc.Length - 5)
  [Array]::Copy($enc, 5, $blob, 0, $blob.Length)
  return [DpapiUtil]::Unprotect($blob)
}
function Decrypt-V10String([byte[]]$key, [string]$b64) {
  $raw = [Convert]::FromBase64String($b64)
  if ([Text.Encoding]::ASCII.GetString($raw,0,3) -ne 'v10') { throw "bad cipher prefix" }
  $nonce = New-Object byte[] 12; [Array]::Copy($raw,3,$nonce,0,12)
  $ctLen = $raw.Length - 3 - 12 - 16
  if ($ctLen -lt 0) { throw 'cipher too short' }
  $ct = New-Object byte[] $ctLen; [Array]::Copy($raw,15,$ct,0,$ctLen)
  $tag = New-Object byte[] 16; [Array]::Copy($raw,$raw.Length-16,$tag,0,16)
  return [Text.Encoding]::UTF8.GetString([AesGcmBCrypt]::Decrypt($key,$nonce,$ct,$tag))
}
function Get-JwtExp([string]$jwt) {
  $parts = $jwt.Split('.')
  if ($parts.Length -lt 2) { return $null }
  $p = $parts[1].Replace('-','+').Replace('_','/')
  switch ($p.Length % 4) { 2 { $p += '==' } 3 { $p += '=' } 0 { } default { $p += '===' } }
  $obj = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p))) | ConvertFrom-Json
  return [int64]$obj.exp
}
function New-CursorChecksum([string]$machineId) {
  $t = [int64][Math]::Floor(([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) / 1000000.0)
  $r = New-Object byte[] 6
  $r[0] = [byte](($t -shr 40) -band 255)
  $r[1] = [byte](($t -shr 32) -band 255)
  $r[2] = [byte](($t -shr 24) -band 255)
  $r[3] = [byte](($t -shr 16) -band 255)
  $r[4] = [byte](($t -shr 8) -band 255)
  $r[5] = [byte]($t -band 255)
  $seed = 165
  for ($i=0; $i -lt $r.Length; $i++) {
    $v = (($r[$i] -bxor $seed) + ($i % 256)) -band 255
    $r[$i] = [byte]$v
    $seed = $v
  }
  $b64 = [Convert]::ToBase64String($r).TrimEnd('=').Replace('+','-').Replace('/','_')
  return "$b64$machineId"
}
function Invoke-ConnectJson([string]$url, [hashtable]$headers, [string]$body='{}') {
  $req = [Net.HttpWebRequest]::Create($url)
  $req.Method = 'POST'
  $req.ContentType = 'application/json'
  $req.Timeout = 30000
  foreach ($k in $headers.Keys) { $req.Headers[$k] = [string]$headers[$k] }
  $bytes = [Text.Encoding]::UTF8.GetBytes($body)
  $req.ContentLength = $bytes.Length
  $s = $req.GetRequestStream(); $s.Write($bytes,0,$bytes.Length); $s.Close()
  try {
    $resp = $req.GetResponse()
    $sr = New-Object IO.StreamReader($resp.GetResponseStream())
    $text = $sr.ReadToEnd(); $sr.Close(); $resp.Close()
    return @{ ok=$true; status=[int]$resp.StatusCode; text=$text }
  } catch [Net.WebException] {
    $ex = $_.Exception
    $status = $null; $text = $ex.Message
    if ($ex.Response) {
      $status = [int]$ex.Response.StatusCode
      $sr = New-Object IO.StreamReader($ex.Response.GetResponseStream())
      $text = $sr.ReadToEnd(); $sr.Close()
      $ex.Response.Close()
    }
    return @{ ok=$false; status=$status; text=$text }
  }
}
function Convert-ProtoTs($v) {
  if ($null -eq $v) { return $null }
  if ($v -is [string]) {
    $s = $v.Trim()
    # numeric epoch as string (Connect sometimes emits int64 as JSON string)
    if ($s -match '^\d{10,16}$') {
      $n = [int64]$s
      if ($n -gt 1000000000000) { return $n }
      if ($n -gt 1000000000) { return ($n * 1000) }
      return $n
    }
    try {
      $dto = [DateTimeOffset]::Parse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
      return $dto.ToUnixTimeMilliseconds()
    } catch {
      return $null
    }
  }
  if ($v -is [long] -or $v -is [int] -or $v -is [decimal] -or $v -is [double]) {
    $n = [int64]$v
    if ($n -gt 1000000000000) { return $n } # already ms
    if ($n -gt 1000000000) { return ($n * 1000) } # seconds
    return $n
  }
  if ($v.PSObject -and ($v.PSObject.Properties.Name -contains 'seconds' -or $v.PSObject.Properties.Name -contains 'Seconds')) {
    $sec = if ($v.seconds -ne $null) { [int64]$v.seconds } else { [int64]$v.Seconds }
    $nanos = 0
    if ($v.nanos -ne $null) { $nanos = [int64]$v.nanos }
    elseif ($v.Nanos -ne $null) { $nanos = [int64]$v.Nanos }
    return ($sec * 1000) + [int64][Math]::Floor($nanos / 1e6)
  }
  return $null
}
function Format-PtFromMs([nullable[int64]]$ms) {
  if ($null -eq $ms -or $ms -le 0) { return $null }
  $dto = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$ms).ToOffset([TimeSpan]::FromHours(-7))
  # America/Los_Angeles approx; prefer TimeZoneInfo when available
  try {
    $tz = [TimeZoneInfo]::FindSystemTimeZoneById('Pacific Standard Time')
    $local = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::FromUnixTimeMilliseconds([int64]$ms), $tz)
    return $local.ToString('yyyy-MM-dd h:mm tt') + ' PT'
  } catch {
    return $dto.ToString('yyyy-MM-dd h:mm tt') + ' PT'
  }
}

Write-Host '=== Grok Bot DashboardService collector (read-only) ==='
$key = Get-OsCryptKey
Write-Host ("os_crypt key len={0}" -f $key.Length)

$secretsPath = Join-Path $env:APPDATA 'Grok Bot\sand-secrets.json'
$secrets = Get-Content $secretsPath -Raw | ConvertFrom-Json
$accounts = ($secrets.'cursor-accounts' | ConvertFrom-Json)
$active = $accounts.active
$acct = $accounts.accounts.$active
$access = Decrypt-V10String $key $acct.'cursor-access-token'
$refresh = Decrypt-V10String $key $acct.'cursor-refresh-token'
$machineId = Decrypt-V10String $key $secrets.'cursor-machine-id'
Write-Host ("tokens: access len={0} prefix={1}… refresh len={2} machineId len={3} prefix={4}" -f $access.Length, $access.Substring(0,4), $refresh.Length, $machineId.Length, $machineId.Substring(0,[Math]::Min(8,$machineId.Length)))

$clientId = 'KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB'
$backend = 'https://api2.cursor.sh'
$appVersion = '0.43.0'
$markerPath = Join-Path $env:APPDATA 'Grok Bot\sand-session-marker.json'
if (Test-Path $markerPath) {
  $mark = Get-Content $markerPath -Raw | ConvertFrom-Json
  if ($mark.appVersion) { $appVersion = [string]$mark.appVersion }
}

$exp = Get-JwtExp $access
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Write-Host ("jwt exp={0} now={1} remaining_s={2}" -f $exp, $now, ($exp - $now))
if ($null -eq $exp -or $exp -le ($now + 60)) {
  Write-Host 'Refreshing OAuth access token...'
  $bodyObj = @{ client_id = $clientId; grant_type = 'refresh_token'; refresh_token = $refresh }
  $refreshBody = $bodyObj | ConvertTo-Json -Compress
  $tr = Invoke-ConnectJson "$backend/oauth/token" @{} $refreshBody
  if (-not $tr.ok) {
    $safe = $tr.text -replace '(?i)"(access|refresh)_token"\s*:\s*"[^"]*"','"$1_token":"[REDACTED]"'
    throw "oauth refresh failed status=$($tr.status) body=$safe"
  }
  $tok = $tr.text | ConvertFrom-Json
  if (-not $tok.access_token) { throw 'refresh response missing access_token' }
  $access = [string]$tok.access_token
  Write-Host ("refresh OK access len={0} prefix={1}…" -f $access.Length, $access.Substring(0,4))
  if ($tok.refresh_token) { $refresh = [string]$tok.refresh_token }
} else {
  Write-Host 'Access token valid; no refresh'
}

$checksum = New-CursorChecksum $machineId
$hdr = @{
  'authorization' = "Bearer $access"
  'connect-protocol-version' = '1'
  'x-cursor-client-type' = 'sand'
  'x-cursor-client-version' = $appVersion
  'x-cursor-client-source' = 'sand-desktop'
  'x-cursor-checksum' = $checksum
  'x-request-id' = [guid]::NewGuid().ToString()
  'x-ghost-mode' = 'true'
}
# selected team if present (encrypted field name from research)
if ($acct.PSObject.Properties.Name -contains 'cursor-selected-team-id' -and $acct.'cursor-selected-team-id') {
  try {
    $teamId = Decrypt-V10String $key $acct.'cursor-selected-team-id'
    if ($teamId) { $hdr['x-cursor-team-id'] = $teamId; Write-Host ("team id attached len={0}" -f $teamId.Length) }
  } catch { Write-Host "team id skip: $($_.Exception.Message)" }
}

$u1 = Invoke-ConnectJson "$backend/aiserver.v1.DashboardService/GetSandUsageStatus" $hdr '{}'
Write-Host ("GetSandUsageStatus status={0} ok={1}" -f $u1.status, $u1.ok)
if (-not $u1.ok) { throw "GetSandUsageStatus failed: $($u1.status) $($u1.text)" }
$u2 = Invoke-ConnectJson "$backend/aiserver.v1.DashboardService/GetCurrentPeriodUsage" $hdr '{}'
Write-Host ("GetCurrentPeriodUsage status={0} ok={1}" -f $u2.status, $u2.ok)
if (-not $u2.ok) { Write-Host "WARN GetCurrentPeriodUsage failed: $($u2.status) $($u2.text)" }

$sand = $u1.text | ConvertFrom-Json
$period = $null
if ($u2.ok -and $u2.text) { $period = $u2.text | ConvertFrom-Json }

# Field names: JSON Connect uses proto json names (camelCase) or original — accept both
$usagePct = $null
foreach ($n in @('usagePercent','usage_percent','percentUsed','percent_used')) {
  if ($sand.PSObject.Properties.Name -contains $n -and $null -ne $sand.$n) { $usagePct = [double]$sand.$n; break }
}
$nextResetMs = $null
foreach ($n in @('nextResetTimestampUtc','next_reset_timestamp_utc','nextResetMs','next_reset_ms')) {
  if ($sand.PSObject.Properties.Name -contains $n -and $null -ne $sand.$n) { $nextResetMs = Convert-ProtoTs $sand.$n; break }
}

$usedCents = $null; $limitCents = $null; $billingEndMs = $null
if ($period) {
  foreach ($n in @('billingCycleEnd','billing_cycle_end')) {
    if ($period.PSObject.Properties.Name -contains $n -and $null -ne $period.$n) { $billingEndMs = Convert-ProtoTs $period.$n; break }
  }
  $slu = $null
  foreach ($n in @('spendLimitUsage','spend_limit_usage')) {
    if ($period.PSObject.Properties.Name -contains $n) { $slu = $period.$n; break }
  }
  if ($slu) {
    foreach ($n in @('individualUsed','individual_used')) {
      if ($slu.PSObject.Properties.Name -contains $n -and $null -ne $slu.$n) { $usedCents = [int]$slu.$n; break }
    }
    foreach ($n in @('individualLimit','individual_limit')) {
      if ($slu.PSObject.Properties.Name -contains $n -and $null -ne $slu.$n) { $limitCents = [int]$slu.$n; break }
    }
  }
}

$nowUtc = [DateTimeOffset]::UtcNow
$tz = [TimeZoneInfo]::FindSystemTimeZoneById('Pacific Standard Time')
$nowPt = [TimeZoneInfo]::ConvertTime($nowUtc, $tz)

$usedUsd = if ($null -ne $usedCents) { [math]::Round($usedCents / 100.0, 2) } else { $null }
$limitUsd = if ($null -ne $limitCents) { [math]::Round($limitCents / 100.0, 2) } else { $null }
$resetsInDays = $null
if ($null -ne $nextResetMs -and $nextResetMs -gt 0) {
  $resetsInDays = [math]::Round(([DateTimeOffset]::FromUnixTimeMilliseconds([int64]$nextResetMs) - $nowUtc).TotalDays, 1)
}

$live = [ordered]@{
  weekly_usage_pct = $usagePct
  resets_in_days = $resetsInDays
  next_reset_ms = $nextResetMs
  next_reset_pt = (Format-PtFromMs $nextResetMs)
  on_demand_spend_usd = $usedUsd
  on_demand_limit_usd = $limitUsd
  on_demand_used_cents = $usedCents
  on_demand_limit_cents = $limitCents
  billing_cycle_end_ms = $billingEndMs
  billing_cycle_end_pt = (Format-PtFromMs $billingEndMs)
  captured_at = $nowUtc.ToString('o')
  captured_at_pt = $nowPt.ToString('yyyy-MM-dd h:mm:ss tt') + ' PT'
  source = 'dashboard_rpc'
  app_version = $appVersion
  raw_keys_sand = @($sand.PSObject.Properties.Name)
}

New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
($live | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $LivePath -Encoding UTF8
Write-Host ("Wrote {0}" -f $LivePath)
Write-Host ("weekly={0}% resets_in={1}d on_demand={2}/{3} USD" -f $usagePct, $resetsInDays, $usedUsd, $limitUsd)

# Merge into spend.json
if (-not (Test-Path -LiteralPath $SpendPath)) { throw "missing $SpendPath" }
$spend = Get-Content -LiteralPath $SpendPath -Raw | ConvertFrom-Json
$currentParts = @()
if ($null -ne $usagePct) { $currentParts += ("weekly {0}%" -f ([math]::Round($usagePct,1))) }
if ($null -ne $usedUsd -and $null -ne $limitUsd) { $currentParts += ("on-demand `${0} / `${1}" -f $usedUsd, $limitUsd) }
elseif ($null -ne $usedUsd) { $currentParts += ("on-demand `${0}" -f $usedUsd) }
$current = if ($currentParts.Count) { $currentParts -join ' | ' } else { $null }
$nextReset = if ($live.next_reset_pt) { $live.next_reset_pt } elseif ($null -ne $resetsInDays) { "~$resetsInDays days" } else { $null }

$rowUpdate = @{
  id = 'grok-cursor'
  account = 'Grok Bot / Cursor'
  sub_level = 'weekly usage + on-demand'
  limit_period = 'week'
  current = $current
  next_reset = $nextReset
  status = 'OK'
  note = 'DashboardService GetSandUsageStatus + GetCurrentPeriodUsage (local decrypt, free RPC)'
  source = 'dashboard_rpc'
}
$found = $false
foreach ($r in $spend.rows) {
  if ($r.id -eq 'grok-cursor') {
    foreach ($k in $rowUpdate.Keys) { $r | Add-Member -NotePropertyName $k -NotePropertyValue $rowUpdate[$k] -Force }
    $found = $true
    break
  }
}
if (-not $found) { $spend.rows += (New-Object psobject -Property $rowUpdate) }
$spend.updated_at = $nowUtc.ToString('o')
$spend.updated_at_pt = $nowPt.ToString('yyyy-MM-dd h:mm:ss tt') + ' PT'
if (-not $spend.meta) { $spend | Add-Member -NotePropertyName meta -NotePropertyValue (@{}) }
$spend.meta | Add-Member -NotePropertyName last_grok_dashboard_rpc -NotePropertyValue $spend.updated_at -Force
($spend | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $SpendPath -Encoding UTF8
Write-Host ("Merged grok-cursor into {0}" -f $SpendPath)
Write-Host 'DONE'




