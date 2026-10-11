$ErrorActionPreference = 'Stop'

$dataRoot = if ($env:COURIERCMS_LOCAL_DATA_PATH) {
  $env:COURIERCMS_LOCAL_DATA_PATH
} else {
  Join-Path $env:LOCALAPPDATA 'CourierCMS'
}

$env:COURIERCMS_RELEASE_PROFILE = 'local'
$env:COURIERCMS_LOCAL_DATA_PATH = $dataRoot
$releaseCommand = Join-Path $PSScriptRoot 'bin\couriercms.bat'
$pidPath = Join-Path $dataRoot 'couriercms.pid'
$releaseCookiePath = Join-Path $dataRoot 'release-cookie.txt'

if (Test-Path -LiteralPath $releaseCookiePath) {
  $env:RELEASE_COOKIE = (Get-Content -LiteralPath $releaseCookiePath -Raw).Trim()
}

if (Test-Path -LiteralPath $pidPath) {
  & $releaseCommand stop
  if ($LASTEXITCODE -ne 0) {
    Write-Warning 'The release stop command did not find a running CourierCMS node.'
  }
} else {
  Write-Host 'CourierCMS is not recorded as running.'
}

if (Test-Path -LiteralPath $pidPath) { Remove-Item -LiteralPath $pidPath -Force }
Write-Host 'CourierCMS has stopped.'
