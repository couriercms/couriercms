param(
  [string]$FromVersion = '0.1.0-upgrade-a',
  [string]$ToVersion = '0.1.0-upgrade-b',
  [int]$Port = 4110
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$temporaryRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot '.tmp\local-upgrade-test'))
$allowedRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot '.tmp'))
$originalPath = $env:Path
$runningPackage = $null

if (-not $temporaryRoot.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Local upgrade test path must remain inside the repository .tmp directory.'
}

function Invoke-ReleaseBuild([string]$Version) {
  & (Join-Path $PSScriptRoot 'build-local-release.ps1') -Version $Version
  if ($LASTEXITCODE -ne 0) { throw "Local release build $Version failed." }
}

function Start-TestRelease([string]$PackagePath) {
  $script:runningPackage = $PackagePath
  & (Join-Path $PackagePath 'start-couriercms.ps1') -NoBrowser -StartupTimeoutSeconds 45
  if ($LASTEXITCODE -ne 0) { throw "Local release at $PackagePath failed to start." }

  $response = Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$Port/health/ready"
  if ($response.StatusCode -ne 200) { throw 'Local release did not report ready.' }
}

function Stop-TestRelease {
  if ($script:runningPackage) {
    & (Join-Path $script:runningPackage 'stop-couriercms.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Local release failed to stop cleanly.' }
    $script:runningPackage = $null
  }
}

function Get-StateFingerprint([string]$PackagePath) {
  $output = & (Join-Path $PackagePath 'bin\couriercms.bat') eval `
    'IO.puts(CourierCMS.Release.local_state_fingerprint())'

  if ($LASTEXITCODE -ne 0) { throw 'Could not read the Local durable-state fingerprint.' }

  $fingerprint = $output | Select-String -Pattern '^[0-9a-f]{64}$' | Select-Object -Last 1
  if (-not $fingerprint) { throw 'The Local durable-state fingerprint was not returned.' }
  $fingerprint.Line
}

function Get-RequiredFileHash([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Expected durable Local file is missing: $Path"
  }

  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

try {
  if (Test-Path -LiteralPath $temporaryRoot) {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
  }

  $dataRoot = Join-Path $temporaryRoot 'data'
  $preservedPackage = Join-Path $temporaryRoot 'from-release'
  $backupPath = Join-Path $temporaryRoot 'pre-upgrade.zip'
  New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null

  $env:COURIERCMS_LOCAL_DATA_PATH = $dataRoot
  $env:PORT = [string]$Port
  $env:COURIERCMS_RELEASE_PROFILE = 'local'

  Invoke-ReleaseBuild $FromVersion
  $builtFromPackage = Join-Path $repositoryRoot ".tmp\local-release\couriercms-$FromVersion-windows-x64"
  Copy-Item -LiteralPath $builtFromPackage -Destination $preservedPackage -Recurse

  Start-TestRelease $preservedPackage
  Stop-TestRelease

  $beforeFingerprint = Get-StateFingerprint $preservedPackage
  $beforeSecretsHash = Get-RequiredFileHash (Join-Path $dataRoot 'installation-secrets.json')
  $beforeCookieHash = Get-RequiredFileHash (Join-Path $dataRoot 'release-cookie.txt')

  & (Join-Path $preservedPackage 'backup-couriercms.ps1') -Destination $backupPath
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
    throw 'The pre-upgrade Local backup was not created.'
  }

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $backup = [System.IO.Compression.ZipFile]::OpenRead($backupPath)
  try {
    $backupEntries = $backup.Entries.FullName
    foreach ($requiredEntry in @('couriercms.db', 'installation-secrets.json', 'release-cookie.txt')) {
      if ($requiredEntry -notin $backupEntries) {
        throw "The Local backup is missing $requiredEntry."
      }
    }
  } finally {
    $backup.Dispose()
  }

  Invoke-ReleaseBuild $ToVersion
  $upgradedPackage = Join-Path $repositoryRoot ".tmp\local-release\couriercms-$ToVersion-windows-x64"

  # The second artifact must run using only its bundled Erlang runtime.
  $env:Path = "$env:SystemRoot\System32;$env:SystemRoot"
  Start-TestRelease $upgradedPackage
  Stop-TestRelease

  # A second restart catches startup-only migration or reconciliation failures.
  Start-TestRelease $upgradedPackage
  Stop-TestRelease

  $afterFingerprint = Get-StateFingerprint $upgradedPackage
  $afterSecretsHash = Get-RequiredFileHash (Join-Path $dataRoot 'installation-secrets.json')
  $afterCookieHash = Get-RequiredFileHash (Join-Path $dataRoot 'release-cookie.txt')

  if ($beforeFingerprint -ne $afterFingerprint) {
    throw 'Durable Local database identity changed across the release upgrade.'
  }
  if ($beforeSecretsHash -ne $afterSecretsHash) {
    throw 'Local installation encryption material changed across the release upgrade.'
  }
  if ($beforeCookieHash -ne $afterCookieHash) {
    throw 'Local release identity changed across the release upgrade.'
  }

  Write-Host "Local upgrade and persistence test passed: $FromVersion -> $ToVersion"
} finally {
  $env:Path = $originalPath
  if ($runningPackage) {
    try { Stop-TestRelease } catch { Write-Warning $_ }
  }
}
