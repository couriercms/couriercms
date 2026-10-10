$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
& (Join-Path $PSScriptRoot 'prepare-extensions.ps1') -IncludeFake
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$env:COURIERCMS_EXTENSIONS_PATH = Join-Path $repositoryRoot '.local\extensions'
Push-Location (Join-Path $repositoryRoot 'platform')
try {
  mix setup
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  mix phx.server
} finally { Pop-Location }
