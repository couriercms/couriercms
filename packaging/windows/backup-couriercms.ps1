param([string]$Destination)

$ErrorActionPreference = 'Stop'
$dataRoot = if ($env:COURIERCMS_LOCAL_DATA_PATH) {
  $env:COURIERCMS_LOCAL_DATA_PATH
} else {
  Join-Path $env:LOCALAPPDATA 'CourierCMS'
}

& (Join-Path $PSScriptRoot 'stop-couriercms.ps1')

if (-not $Destination) {
  $backupRoot = Join-Path (Split-Path $dataRoot -Parent) 'CourierCMS Backups'
  New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
  $Destination = Join-Path $backupRoot ("couriercms-{0}.zip" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("couriercms-backup-{0}" -f [guid]::NewGuid())
New-Item -ItemType Directory -Path $stagingRoot | Out-Null

try {
  foreach ($name in @('couriercms.db', 'couriercms.db-wal', 'couriercms.db-shm', 'installation-secrets.json', 'release-cookie.txt')) {
    $source = Join-Path $dataRoot $name
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $stagingRoot }
  }

  $extensions = Join-Path $dataRoot 'extensions'
  if (Test-Path -LiteralPath $extensions) {
    Copy-Item -LiteralPath $extensions -Destination $stagingRoot -Recurse
  }

  Compress-Archive -Path (Join-Path $stagingRoot '*') -DestinationPath $Destination -Force
} finally {
  Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}

Write-Host "CourierCMS backup created at $Destination"
