# HTTPS desk host for AI Spend Tracker using mkcert PFX (no admin/netsh).
# TLS on https://127.0.0.1:8787/ -> HTTP backend on 127.0.0.1:18787
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$CacheDir = Join-Path $Root 'cache'
if (-not (Test-Path -LiteralPath $CacheDir)) { New-Item -ItemType Directory -Path $CacheDir | Out-Null }
$LogPath = Join-Path $CacheDir 'https_host.log'
function Write-HttpsLog([string]$msg) {
  $line = ('{0} {1}' -f (Get-Date -Format o), $msg)
  try { Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 } catch {}
  Write-Host $line
}

try {
  $PfxPath = Join-Path $Root 'certs\localhost.pfx'
  $PfxPass = 'spendlocal'
  $HttpsPort = 8787
  $BackendPort = 18787
  $Serve = Join-Path $Root 'serve.ps1'

  Write-HttpsLog 'starting serve_https.ps1'
  if (-not (Test-Path -LiteralPath $PfxPath)) { throw "Missing $PfxPath" }
  if (-not (Test-Path -LiteralPath $Serve)) { throw "Missing $Serve" }

  function Test-Backend {
    try {
      $r = Invoke-WebRequest -Uri ("http://127.0.0.1:{0}/api/health" -f $script:BackendPort) -UseBasicParsing -TimeoutSec 1
      return ($r.StatusCode -eq 200)
    } catch { return $false }
  }

  if (-not (Test-Backend)) {
    Write-HttpsLog ("starting backend on {0}" -f $BackendPort)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Serve`""
    $psi.WorkingDirectory = $Root
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['SPEND_TRACKER_PORT'] = "$BackendPort"
    $bp = [System.Diagnostics.Process]::Start($psi)
    Write-HttpsLog ("backend pid {0}" -f $bp.Id)
    $deadline = (Get-Date).AddSeconds(12)
    while ((Get-Date) -lt $deadline) {
      if (Test-Backend) { break }
      Start-Sleep -Milliseconds 300
    }
    if (-not (Test-Backend)) { throw "HTTP backend failed to start on $BackendPort" }
    Write-HttpsLog 'backend healthy'
  } else {
    Write-HttpsLog 'backend already healthy'
  }

  $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
    $PfxPath,
    $PfxPass,
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
  )
  Write-HttpsLog ("cert loaded subject={0} hasKey={1}" -f $cert.Subject, $cert.HasPrivateKey)

  $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback), $HttpsPort
  $listener.Start()
  Write-HttpsLog ("listening https://127.0.0.1:{0}/" -f $HttpsPort)

  function Handle-Client([System.Net.Sockets.TcpClient]$client) {
    $backend = $null
    $ssl = $null
    try {
      $net = $client.GetStream()
      $ssl = New-Object System.Net.Security.SslStream($net, $false)
      $ssl.AuthenticateAsServer($cert, $false, [System.Security.Authentication.SslProtocols]::Tls12, $false)
      $backend = New-Object System.Net.Sockets.TcpClient
      $backend.Connect('127.0.0.1', $script:BackendPort)
      $b = $backend.GetStream()
      $buf = New-Object byte[] 16384
      $ms = New-Object System.IO.MemoryStream
      $ssl.ReadTimeout = 60000
      $b.ReadTimeout = 60000

      while ($true) {
        $n = $ssl.Read($buf, 0, $buf.Length)
        if ($n -le 0) { return }
        $ms.Write($buf, 0, $n)
        $arr = $ms.ToArray()
        $txt = [Text.Encoding]::ASCII.GetString($arr)
        if ($txt.Contains("`r`n`r`n")) {
          $need = 0
          if ($txt -match '(?im)^Content-Length:\s*(\d+)') { $need = [int]$Matches[1] }
          $idx = $txt.IndexOf("`r`n`r`n")
          $have = $arr.Length - ($idx + 4)
          while ($have -lt $need) {
            $n2 = $ssl.Read($buf, 0, $buf.Length)
            if ($n2 -le 0) { break }
            $ms.Write($buf, 0, $n2)
            $have += $n2
          }
          break
        }
      }
      $req = $ms.ToArray()
      $reqText = [Text.Encoding]::ASCII.GetString($req)
      $reqText = [regex]::Replace($reqText, '(?im)^Host:.*$', ("Host: 127.0.0.1:{0}" -f $script:BackendPort))
      $reqBytes = [Text.Encoding]::ASCII.GetBytes($reqText)
      $b.Write($reqBytes, 0, $reqBytes.Length)

      while ($true) {
        try { $n = $b.Read($buf, 0, $buf.Length) } catch { break }
        if ($n -le 0) { break }
        $ssl.Write($buf, 0, $n)
        $ssl.Flush()
      }
    } catch {
      Write-HttpsLog ("client error: {0}" -f $_.Exception.Message)
    } finally {
      try { if ($ssl) { $ssl.Close() } } catch {}
      try { $client.Close() } catch {}
      try { if ($backend) { $backend.Close() } } catch {}
    }
  }

  while ($true) {
    $c = $listener.AcceptTcpClient()
    Handle-Client $c
  }
} catch {
  Write-HttpsLog ("FATAL: {0}" -f $_.Exception.ToString())
  throw
}
