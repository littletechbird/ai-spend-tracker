# Open AI Spend Tracker as a standalone desktop dialog (no browser chrome).
# Uses Edge/Chrome --app mode at a dialog-ish size - not fullscreen, not a tab.
$ErrorActionPreference = 'Stop'
$Url = 'http://127.0.0.1:8787/?desk=1'
$Width = 1100
$Height = 720
$PosX = 120
$PosY = 80

function Wait-Healthy {
  $deadline = (Get-Date).AddSeconds(20)
  while ((Get-Date) -lt $deadline) {
    try {
      $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8787/api/health' -UseBasicParsing -TimeoutSec 2
      if ($r.StatusCode -eq 200) { return $true }
    } catch { }
    Start-Sleep -Milliseconds 400
  }
  return $false
}

function Find-Chromium {
  $pf86 = ${env:ProgramFiles(x86)}
  $candidates = @(
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $pf86 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:LocalAppData 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $pf86 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LocalAppData 'Google\Chrome\Application\chrome.exe')
  )
  foreach ($p in $candidates) {
    if ($p -and (Test-Path -LiteralPath $p)) { return $p }
  }
  return $null
}

if (-not (Wait-Healthy)) {
  Write-Host 'Host not up on :8787 - start serve.ps1 / START.bat first.'
  exit 1
}

$browser = Find-Chromium
if (-not $browser) {
  Start-Process $Url
  Write-Host 'No Edge/Chrome found; opened default browser tab.'
  exit 0
}

$dataDir = Join-Path $env:LOCALAPPDATA 'AI-Spend-Tracker\chromium-app'
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

$argList = @(
  ("--app=" + $Url),
  ("--window-size=" + $Width + "," + $Height),
  ("--window-position=" + $PosX + "," + $PosY),
  ("--user-data-dir=" + $dataDir),
  '--no-first-run',
  '--disable-features=TranslateUI'
)

Start-Process -FilePath $browser -ArgumentList $argList | Out-Null
$leaf = Split-Path $browser -Leaf
Write-Host ('Opened desktop dialog via ' + $leaf + ' ' + $Width + 'x' + $Height)
