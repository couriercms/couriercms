param(
  [switch]$NoBrowser,
  [int]$StartupTimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'

$installRoot = $PSScriptRoot
$dataRoot = if ($env:COURIERCMS_LOCAL_DATA_PATH) {
  $env:COURIERCMS_LOCAL_DATA_PATH
} else {
  Join-Path $env:LOCALAPPDATA 'CourierCMS'
}

$env:COURIERCMS_RELEASE_PROFILE = 'local'
$env:COURIERCMS_LOCAL_DATA_PATH = $dataRoot
$env:PHX_SERVER = 'true'
if (-not $env:PORT) { $env:PORT = '4000' }

$extensionsPath = Join-Path $dataRoot 'extensions'
$logsPath = Join-Path $dataRoot 'logs'
New-Item -ItemType Directory -Force -Path $extensionsPath, $logsPath | Out-Null

$releaseCookiePath = Join-Path $dataRoot 'release-cookie.txt'
if (-not (Test-Path -LiteralPath $releaseCookiePath)) {
  [guid]::NewGuid().ToString('N') | Set-Content -LiteralPath $releaseCookiePath -NoNewline
}
$env:RELEASE_COOKIE = (Get-Content -LiteralPath $releaseCookiePath -Raw).Trim()

Get-ChildItem -LiteralPath (Join-Path $installRoot 'bundled-extensions') -Filter '*.couriercms' -File |
  Copy-Item -Destination $extensionsPath -Force

$releaseCommand = Join-Path $installRoot 'bin\couriercms.bat'
& $releaseCommand eval 'CourierCMS.Release.migrate()'
if ($LASTEXITCODE -ne 0) { throw 'CourierCMS could not initialize its Local database.' }

$standardOutput = Join-Path $logsPath 'couriercms.log'
$standardError = Join-Path $logsPath 'couriercms-error.log'
$arguments = "/c `"`"$releaseCommand`" start`""

$process = Start-Process -FilePath $env:ComSpec -ArgumentList $arguments -WindowStyle Hidden `
  -RedirectStandardOutput $standardOutput -RedirectStandardError $standardError -PassThru

$deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
$dashboardUrl = "http://127.0.0.1:$($env:PORT)/"
$ready = $false

while ([DateTime]::UtcNow -lt $deadline -and -not $process.HasExited) {
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri ($dashboardUrl + 'health/ready') -TimeoutSec 2
    if ($response.StatusCode -eq 200) { $ready = $true; break }
  } catch {
    Start-Sleep -Milliseconds 500
  }
}

if (-not $ready) {
  if (-not $process.HasExited) { Stop-Process -Id $process.Id }
  Write-Error "CourierCMS did not become ready. Review $standardError and $standardOutput."
  exit 1
}

Set-Content -LiteralPath (Join-Path $dataRoot 'couriercms.pid') -Value $process.Id
Write-Host "CourierCMS is running at $dashboardUrl"
Write-Host "Local data: $dataRoot"
if (-not $NoBrowser) {
  Start-Process $dashboardUrl
}
