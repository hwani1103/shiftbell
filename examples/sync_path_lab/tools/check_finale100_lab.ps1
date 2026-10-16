param([switch]$Build,[switch]$SkipChecks,[string]$FlutterRoot='C:/tools/flutter',
      [string]$Python='C:/Users/Administrator/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe')
$ErrorActionPreference='Stop'
if($SkipChecks -and -not $Build){throw '-SkipChecks requires -Build'}
$lab=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repo=(Resolve-Path (Join-Path $lab '../..')).Path
$evidence=Join-Path $repo 'docs/next_version_27이후/game_implementation_v11'
$dart=Join-Path $FlutterRoot 'bin/cache/dart-sdk/bin/dart.exe'
$snapshot=Join-Path $FlutterRoot 'bin/cache/flutter_tools.snapshot'
$oldCache=$env:PUB_CACHE; $oldRoot=$env:FLUTTER_ROOT; $oldCi=$env:CI
$env:PUB_CACHE=Join-Path $repo 'packages/sync_path_core/.pub-cache'
$env:FLUTTER_ROOT=$FlutterRoot; $env:CI='true'
function Run([string]$folder,[string]$log,[string[]]$arguments,[bool]$flutter=$false) {
  Push-Location (Join-Path $repo $folder)
  try {
    if($flutter) {& $dart $snapshot --no-version-check --suppress-analytics @arguments 2>&1 | Tee-Object -FilePath (Join-Path $evidence $log)}
    else {& $dart @arguments 2>&1 | Tee-Object -FilePath (Join-Path $evidence $log)}
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
    if($active.Count -eq 0) {Write-Output 'BUILD GUARD: no active Flutter/Gradle build';return}
    $identity=($active | ForEach-Object {$_.ProcessId}) -join ','
    if($identity -ne $previous) {Write-Output "BUILD GUARD WAIT: existing build $identity";$previous=$identity}
    Start-Sleep -Seconds 5
  }
}
try {
  & $Python -X utf8 (Join-Path $repo 'packages/sync_path_ui/tools/subset_font.py') --check --report (Join-Path $evidence 'font_size_report.json')
  if($LASTEXITCODE -ne 0){throw 'Font coverage/size failed'}
  if(-not $SkipChecks) {
    foreach($name in @('sync_path_core','sync_path_tools')) {
      Run "packages/$name" "$name-analyze.txt" @('analyze')
      Run "packages/$name" "$name-tests.txt" @('test','--reporter','expanded','--concurrency=1')
    }
    $levels=Join-Path $lab 'assets/pilot_levels.json'
    Run 'packages/sync_path_tools' 'gate_regression_verification.txt' @('run','bin/verify_gates50.dart',$levels,(Join-Path $repo 'docs/next_version_27이후/game_implementation_v8/gate_design.json'),(Join-Path $evidence 'gate_regression_verification.json'))
    Run 'packages/sync_path_tools' 'portal_regression_verification.txt' @('run','bin/verify_portals70.dart',$levels,(Join-Path $repo 'docs/next_version_27이후/game_implementation_v10/portal_design.json'),(Join-Path $evidence 'portal_regression_verification.json'))
    Run 'packages/sync_path_tools' 'finale_verification.txt' @('run','bin/verify_finale100.dart',$levels,(Join-Path $evidence 'finale_design.json'),(Join-Path $evidence 'finale_verification.json'))
    foreach($entry in @(@('sync_path_ui','packages/sync_path_ui'),@('lab','examples/sync_path_lab'))) {
      Run $entry[1] "$($entry[0])-pub.txt" @('pub','get','--offline') $true
      Run $entry[1] "$($entry[0])-analyze.txt" @('analyze','--no-pub') $true
      Run $entry[1] "$($entry[0])-tests.txt" @('test','--no-pub','--reporter','expanded','--concurrency=1') $true
    }
  }
  if($Build) {
    Wait-OtherBuilds
    Run 'examples/sync_path_lab' 'android_dev_debug_build.txt' @('build','apk','--debug','--flavor','dev','--no-pub') $true
    Wait-OtherBuilds
    Run 'examples/sync_path_lab' 'web_build.txt' @('build','web','--debug','--no-pub','--no-web-resources-cdn','--dart-define=SYNC_PATH_LAB_ENV=dev','--no-wasm-dry-run') $true
  }
  Write-Output 'PASS: one hundred levels, isolated DEV debug only; no install.'
} finally {$env:PUB_CACHE=$oldCache;$env:FLUTTER_ROOT=$oldRoot;$env:CI=$oldCi}
