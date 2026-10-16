param([switch]$Build,[string]$FlutterRoot='C:/tools/flutter')
$ErrorActionPreference='Stop'
$lab=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repo=(Resolve-Path (Join-Path $lab '../..')).Path
$evidence=Join-Path $repo 'docs/next_version_27이후/game_implementation_v4'
$dart=Join-Path $FlutterRoot 'bin/cache/dart-sdk/bin/dart.exe'
$snapshot=Join-Path $FlutterRoot 'bin/cache/flutter_tools.snapshot'
$oldCache=$env:PUB_CACHE
$oldRoot=$env:FLUTTER_ROOT
$oldCi=$env:CI
$env:PUB_CACHE=Join-Path $repo 'packages/sync_path_core/.pub-cache'
$env:FLUTTER_ROOT=$FlutterRoot
$env:CI='true'
function Invoke-Check([string]$folder,[string]$log,[string[]]$arguments) {
  Push-Location $folder
  try {
    & $dart @arguments 2>&1 | Tee-Object -FilePath (Join-Path $evidence $log)
    if($LASTEXITCODE -ne 0) {throw "Check failed: $log (exit $LASTEXITCODE)"}
  } finally {Pop-Location}
}
try {
  foreach($name in @('sync_path_core','sync_path_tools')) {
    $folder=Join-Path $repo "packages/$name"
    Invoke-Check $folder "$name-analyze.txt" @('analyze')
    Invoke-Check $folder "$name-tests.txt" @('test','--reporter','expanded')
  }
  Invoke-Check (Join-Path $repo 'packages/sync_path_tools') 'new-level-verification.txt' @(
    'run','bin/verify_campaign.dart',
    (Join-Path $lab 'assets/pilot_levels.json'),(Join-Path $evidence 'level_verification.json'),(Join-Path $evidence 'campaign_design.json'))
  foreach($entry in @(@('sync_path_ui',(Join-Path $repo 'packages/sync_path_ui')),@('lab',$lab))) {
    Invoke-Check $entry[1] "$($entry[0])-analyze.txt" @($snapshot,'--no-version-check','--suppress-analytics','analyze','--no-pub')
    Invoke-Check $entry[1] "$($entry[0])-tests.txt" @($snapshot,'--no-version-check','--suppress-analytics','test','--no-pub','--reporter','expanded')
  }
  if($Build) {
    Invoke-Check $lab 'android_dev_debug_build.txt' @($snapshot,'--no-version-check','--suppress-analytics','build','apk','--debug','--flavor','dev','--no-pub')
    Invoke-Check $lab 'web_build.txt' @($snapshot,'--no-version-check','--suppress-analytics','build','web','--debug','--no-pub','--no-web-resources-cdn','--dart-define=SYNC_PATH_LAB_ENV=dev','--no-wasm-dry-run')
  }
  Write-Output 'PASS: isolated DEV game checks. No release or device install performed.'
} finally {
  $env:PUB_CACHE=$oldCache; $env:FLUTTER_ROOT=$oldRoot; $env:CI=$oldCi
}
