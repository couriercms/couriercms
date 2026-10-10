$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
& (Join-Path $PSScriptRoot 'prepare-extensions.ps1') -IncludeFake
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

foreach ($project in @('sdk', 'fake', 'wordpress', 'sanity')) {
  Push-Location (Join-Path $repositoryRoot "extensions\$project")
  try {
    $env:MIX_ENV = 'test'
    mix deps.get
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    mix format --check-formatted
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    mix compile --warnings-as-errors
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    mix test
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  } finally { Pop-Location }
}

$env:COURIERCMS_EXTENSIONS_PATH = Join-Path $repositoryRoot '.local\extensions'
Push-Location (Join-Path $repositoryRoot 'platform')
try {
  $env:MIX_ENV = 'test'
  mix deps.get
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  mix format --check-formatted
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  mix compile --warnings-as-errors
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  mix test
} finally { Pop-Location }
