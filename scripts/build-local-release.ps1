param([string]$Version = '0.1.0')

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$temporaryRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot '.tmp\local-release'))
$allowedRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot '.tmp'))

if (-not $temporaryRoot.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Local release staging path must remain inside the repository .tmp directory.'
}

& (Join-Path $PSScriptRoot 'prepare-extensions.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$env:COURIERCMS_RELEASE_PROFILE = 'local'
$env:MIX_ENV = 'prod'

Push-Location (Join-Path $repositoryRoot 'platform')
try {
  # Remove stale compiled modules and copied priv files before assembling a
  # distributable artifact (renamed migrations otherwise survive in _build).
  mix clean
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  mix deps.get --only prod
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  mix assets.deploy
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  mix compile --warnings-as-errors
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  mix release --overwrite
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally { Pop-Location }

if (Test-Path -LiteralPath $temporaryRoot) {
  Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
}

$artifactName = "couriercms-$Version-windows-x64"
$stagingPath = Join-Path $temporaryRoot $artifactName
$releasePath = Join-Path $repositoryRoot 'platform\_build\local\prod\rel\couriercms'
New-Item -ItemType Directory -Force -Path $stagingPath | Out-Null
Copy-Item -Path (Join-Path $releasePath '*') -Destination $stagingPath -Recurse

# Every installation generates its own Erlang distribution cookie on first
# launch. Never distribute Mix's build-time cookie in a public artifact.
$buildCookie = Join-Path $stagingPath 'releases\COOKIE'
if (Test-Path -LiteralPath $buildCookie) {
  Remove-Item -LiteralPath $buildCookie -Force
}

$bundledExtensions = Join-Path $stagingPath 'bundled-extensions'
New-Item -ItemType Directory -Force -Path $bundledExtensions | Out-Null
Get-ChildItem -LiteralPath (Join-Path $repositoryRoot '.local\extensions') -Filter '*.couriercms' -File |
  Where-Object { $_.Name -notlike '*_fake-*' } |
  Copy-Item -Destination $bundledExtensions

Copy-Item -LiteralPath (Join-Path $repositoryRoot 'packaging\windows\start-couriercms.ps1') -Destination $stagingPath
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'packaging\windows\stop-couriercms.ps1') -Destination $stagingPath
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'packaging\windows\backup-couriercms.ps1') -Destination $stagingPath
Copy-Item -LiteralPath (Join-Path $repositoryRoot 'packaging\windows\README.txt') -Destination $stagingPath

$outputRoot = Join-Path $repositoryRoot '.tmp\releases'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$archive = Join-Path $outputRoot "$artifactName.zip"
Compress-Archive -Path $stagingPath -DestinationPath $archive -Force
Write-Host "Built Local release: $archive"
