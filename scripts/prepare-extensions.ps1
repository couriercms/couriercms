param(
  [switch]$IncludeFake
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$installPath = Join-Path $repositoryRoot '.local\extensions'
$taskTemp = Join-Path $repositoryRoot '.tmp'
New-Item -ItemType Directory -Force -Path $taskTemp | Out-Null
$env:TEMP = $taskTemp
$env:TMP = $taskTemp
$env:MIX_HOME = Join-Path $taskTemp 'mix'
$env:HEX_HOME = Join-Path $taskTemp 'hex'
$env:REBAR_CACHE_DIR = Join-Path $taskTemp 'rebar3'
$env:ELIXIR_MAKE_CACHE_DIR = Join-Path $taskTemp 'elixir_make'
if ($env:COURIERCMS_CACERTS_PATH -and -not $env:HEX_CACERTS_PATH) {
  $env:HEX_CACERTS_PATH = $env:COURIERCMS_CACERTS_PATH
}
if (-not $env:HEX_CACERTS_PATH) {
  $gitCertificateBundle = 'C:\Program Files\Git\usr\ssl\cert.pem'
  if (Test-Path -LiteralPath $gitCertificateBundle) {
    $env:HEX_CACERTS_PATH = $gitCertificateBundle
  }
}
New-Item -ItemType Directory -Force -Path $installPath | Out-Null

Get-ChildItem -LiteralPath $installPath -Filter '*.couriercms' -File -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

$projects = @('wordpress', 'sanity')
if ($IncludeFake) { $projects += 'fake' }

Push-Location (Join-Path $repositoryRoot 'extensions\sdk')
try {
  $env:MIX_ENV = 'prod'
  mix deps.get
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  mix compile --warnings-as-errors
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally { Pop-Location }

foreach ($project in $projects) {
  Push-Location (Join-Path $repositoryRoot "extensions\$project")
  try {
    $output = Join-Path $installPath "couriercms_$project-0.1.0.couriercms"
    mix deps.get --only prod
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    mix couriercms.extension.build --output $output
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  } finally { Pop-Location }
}

Write-Host "Installed CourierCMS extensions in $installPath"
