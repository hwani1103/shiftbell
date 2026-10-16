param([string]$FlutterRoot='C:/tools/flutter',[string]$Python='C:/Users/Administrator/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe')
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$evidence=Join-Path $repo 'docs/next_version_27이후/game_implementation_v8'
$dart=Join-Path $FlutterRoot 'bin/cache/dart-sdk/bin/dart.exe'
$snapshot=Join-Path $FlutterRoot 'bin/cache/flutter_tools.snapshot'
$env:PUB_CACHE=Join-Path $repo 'packages/sync_path_core/.pub-cache';$env:FLUTTER_ROOT=$FlutterRoot;$env:CI='true'
function Run([string]$folder,[string]$log,[string[]]$arguments,[bool]$flutter=$false){
 Push-Location (Join-Path $repo $folder)
 try {
  if($flutter){& $dart $snapshot --no-version-check --suppress-analytics @arguments 2>&1 | Tee-Object -FilePath (Join-Path $evidence $log)}
  else{& $dart @arguments 2>&1 | Tee-Object -FilePath (Join-Path $evidence $log)}
  if($LASTEXITCODE -ne 0){throw "Failed: $log"}
 } finally {Pop-Location}
}
& $Python -X utf8 (Join-Path $repo 'packages/sync_path_ui/tools/subset_font.py') --report (Join-Path $evidence 'font_size_report.json')
if($LASTEXITCODE -ne 0){throw 'Font subset failed'}
foreach($name in @('sync_path_core','sync_path_tools')){
 Run "packages/$name" "$name-analyze.txt" @('analyze')
 Run "packages/$name" "$name-tests.txt" @('test','--reporter','expanded','--concurrency=1')
}
Run 'packages/sync_path_tools' 'gate-verification-log.txt' @('run','bin/verify_gates50.dart','../../examples/sync_path_lab/assets/pilot_levels.json','../../docs/next_version_27이후/game_implementation_v8/gate_design.json','../../docs/next_version_27이후/game_implementation_v8/gate_verification.json')
foreach($folder in @('packages/sync_path_ui','examples/sync_path_lab')){
 $name=Split-Path $folder -Leaf
 Run $folder "$name-pub.txt" @('pub','get','--offline') $true
 Run $folder "$name-analyze.txt" @('analyze','--no-pub') $true
 Run $folder "$name-tests.txt" @('test','--no-pub','--reporter','expanded','--concurrency=1') $true
}
Write-Output 'PASS: validation only. APK/web/release builds explicitly not run.'
