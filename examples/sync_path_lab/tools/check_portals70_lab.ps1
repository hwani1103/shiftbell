param([switch]$Build,[switch]$SkipChecks,[string]$FlutterRoot='C:/tools/flutter',
      [string]$Python='C:/Users/Administrator/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe')
$ErrorActionPreference='Stop'
if($SkipChecks -and -not $Build){throw '-SkipChecks requires -Build'}
$lab=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repo=(Resolve-Path (Join-Path $lab '../..')).Path
$evidence=Join-Path $repo 'docs/next_version_27이후/game_implementation_v10'
$dart=Join-Path $FlutterRoot 'bin/cache/dart-sdk/bin/dart.exe'
$snapshot=Join-Path $FlutterRoot 'bin/cache/flutter_tools.snapshot'
$oldCache=$env:PUB_CACHE; $oldRoot=$env:FLUTTER_ROOT; $oldCi=$env:CI
$env:PUB_CACHE=Join-Path $repo 'packages/sync_path_core/.pub-cache'
$env:FLUTTER_ROOT=$FlutterRoot; $env:CI='true'
function Invoke-Check([string]$folder,[string]$log,[string[]]$arguments) {
  Push-Location $folder
  try {
    & $dart $snapshot --no-version-check --suppress-analytics @arguments 2>&1 |
      Tee-Object -FilePath (Join-Path $evidence $log)
    if($LASTEXITCODE -ne 0) {throw "Check failed: $log (exit $LASTEXITCODE)"}
  } finally {Pop-Location}
}
function Invoke-DartCheck([string]$folder,[string]$log,[string[]]$arguments) {
  Push-Location $folder
  try {
    & $dart @arguments 2>&1 | Tee-Object -FilePath (Join-Path $evidence $log)
    if($LASTEXITCODE -ne 0) {throw "Check failed: $log (exit $LASTEXITCODE)"}
  } finally {Pop-Location}
}
function Wait-OtherBuilds {
  $previous=''
  while($true) {
    $active=@(Get-CimInstance Win32_Process | Where-Object {
      ($_.Name -eq 'dart.exe' -and $_.CommandLine -match 'flutter_tools.*\bbuild\s') -or
      ($_.Name -eq 'java.exe' -and $_.CommandLine -match 'GradleWrapperMain' -and $_.CommandLine -match '(assemble|bundle|\bbuild\b)')
    })
    if($active.Count -eq 0) {
      Write-Output ('BUILD GUARD: no active Flutter/Gradle build at '+(Get-Date -Format o))
      return
    }
    $identity=($active | ForEach-Object {$_.ProcessId}) -join ','
    if($identity -ne $previous) {Write-Output "BUILD GUARD WAIT: existing build process $identity"; $previous=$identity}
    Start-Sleep -Seconds 5
  }
}
try {
  & $Python -X utf8 (Join-Path $repo 'packages/sync_path_ui/tools/subset_font.py') --check --report (Join-Path $evidence 'font_size_report.json')
  if($LASTEXITCODE -ne 0) {throw 'Font coverage/asset size check failed'}
  if(-not $SkipChecks) {
  foreach($name in @('sync_path_core','sync_path_tools')) {
    $folder=Join-Path $repo "packages/$name"
    Invoke-DartCheck $folder "$name-analyze.txt" @('analyze')
    Invoke-DartCheck $folder "$name-tests.txt" @('test','--reporter','expanded')
  }
  $tools=Join-Path $repo 'packages/sync_path_tools'
  $levels=Join-Path $lab 'assets/pilot_levels.json'
  Invoke-DartCheck $tools 'gate_regression_verification.txt' @('run','bin/verify_gates50.dart',$levels,(Join-Path $repo 'docs/next_version_27이후/game_implementation_v8/gate_design.json'),(Join-Path $evidence 'gate_regression_verification.json'))
  Invoke-DartCheck $tools 'portal_verification.txt' @('run','bin/verify_portals70.dart',$levels,(Join-Path $evidence 'portal_design.json'),(Join-Path $evidence 'portal_verification.json'))
  foreach($entry in @(@('sync_path_ui',(Join-Path $repo 'packages/sync_path_ui')),@('lab',$lab))) {
    Invoke-Check $entry[1] "$($entry[0])-pub.txt" @('pub','get','--offline')
    Invoke-Check $entry[1] "$($entry[0])-analyze.txt" @('analyze','--no-pub')
    Invoke-Check $entry[1] "$($entry[0])-tests.txt" @('test','--no-pub','--reporter','expanded','--concurrency=1')
  }
  }
  if($Build) {
    Wait-OtherBuilds
    Invoke-Check $lab 'android_dev_debug_build.txt' @('build','apk','--debug','--flavor','dev','--no-pub')
    Wait-OtherBuilds
    Invoke-Check $lab 'web_build.txt' @('build','web','--debug','--no-pub','--no-web-resources-cdn','--dart-define=SYNC_PATH_LAB_ENV=dev','--no-wasm-dry-run')
  }
  Write-Output 'PASS: seventy-level portal isolated DEV lab. No release or install.'
} finally {
  $env:PUB_CACHE=$oldCache; $env:FLUTTER_ROOT=$oldRoot; $env:CI=$oldCi
}
