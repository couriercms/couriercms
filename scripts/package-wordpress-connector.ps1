$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$packageDirectory = Join-Path $repositoryRoot '.local\packages'
$packagePath = Join-Path $packageDirectory 'couriercms-connector-0.1.0.zip'
$sourceDirectory = Join-Path $repositoryRoot 'connectors\wordpress'
New-Item -ItemType Directory -Force -Path $packageDirectory | Out-Null
if (Test-Path -LiteralPath $packagePath) { Remove-Item -LiteralPath $packagePath -Force }
Compress-Archive -LiteralPath $sourceDirectory -DestinationPath $packagePath
Write-Host "Built $packagePath"
