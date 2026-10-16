param(
  [string]$Dart = 'C:/tools/flutter/bin/cache/dart-sdk/bin/dart.exe',
  [switch]$Offline,
  [switch]$Web
)
$ErrorActionPreference = 'Stop'
$gameRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$gameCore = Join-Path $gameRoot 'packages/sync_path_core'
$gameTools = Join-Path $gameRoot 'packages/sync_path_tools'
$gameLab = Join-Path $gameRoot 'examples/sync_path_lab'
$gameDesign = Join-Path $gameRoot 'docs/next_version_27이후/game_design_v1'
$gamePreviousCache = $env:PUB_CACHE
$gamePreviousCi = $env:CI
$gameLocalCache = Join-Path $gameCore '.pub-cache'
if (Test-Path -LiteralPath $gameLocalCache) { $env:PUB_CACHE = $gameLocalCache }
$env:CI = 'true'
function Invoke-GameDart {
  param([string]$Directory, [string]$Log, [string[]]$Arguments, [int]$ExpectedExit = 0)
  Push-Location -LiteralPath $Directory
  try {
    & $Dart @Arguments 2>&1 | Tee-Object -FilePath (Join-Path $PSScriptRoot $Log)
    if ($LASTEXITCODE -ne $ExpectedExit) { throw "Game command failed ($LASTEXITCODE): dart $($Arguments -join ' ')" }
  } finally { Pop-Location }
}
try {
  $gamePubArgs = @('pub','get')
  if ($Offline) { $gamePubArgs += '--offline' }
  foreach ($gamePackage in @(@{dir=$gameCore;name='core'},@{dir=$gameTools;name='tools'},@{dir=$gameLab;name='lab'})) {
    Invoke-GameDart $gamePackage.dir "$($gamePackage.name)_pub_get.txt" $gamePubArgs
    Invoke-GameDart $gamePackage.dir "$($gamePackage.name)_analyze.txt" @('analyze')
  }
  # Avoid flutter tool/cache locks and use the local Dart package entrypoint.
  Invoke-GameDart $gameCore 'core_test.txt' @('run','test:test','--reporter','expanded')
  Invoke-GameDart $gameTools 'tools_test.txt' @('run','test:test','--reporter','expanded')
  Invoke-GameDart $gameTools 'pilot_verify.txt' @('run','bin/verify_pilot.dart',(Join-Path $gameDesign '08_pilot_levels.json'),(Join-Path $gameDesign '09_pilot_certificates.json'),(Join-Path $PSScriptRoot 'pilot_verification.json'))
  foreach ($gameSample in @(@{name='success';exit=0},@{name='collision';exit=0},@{name='stale';exit=2})) {
    Invoke-GameDart $gameLab "lab_$($gameSample.name).txt" @('run','bin/simulate.dart',(Join-Path $gameDesign '08_pilot_levels.json'),(Join-Path $PSScriptRoot "lab_$($gameSample.name)_plan.json"),(Join-Path $PSScriptRoot "lab_$($gameSample.name)_trace.json")) $gameSample.exit
  }
  if ($Web) {
    & (Join-Path $gameCore 'tool/prepare_web_fixtures.ps1')
    Invoke-GameDart $gameCore 'web_compile.txt' @('compile','js','-O1','tool/web_smoke.dart','-o',(Join-Path $PSScriptRoot 'web_smoke.js'))
    & node (Join-Path $PSScriptRoot 'web_smoke.js') 2>&1 | Tee-Object -FilePath (Join-Path $PSScriptRoot 'web_smoke.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Web smoke failed' }
  }
  Write-Output 'PASS: isolated game engine verification; no existing app build/install'
} finally {
  $env:PUB_CACHE = $gamePreviousCache
  $env:CI = $gamePreviousCi
}
