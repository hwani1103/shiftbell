param(
    [ValidateSet('reading', 'frame', 'legacy')]
    [string]$Mode = 'reading',
    [string]$FlutterSdk = 'C:\tools\flutter'
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    $dartExecutable = Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
    $flutterSnapshot = Join-Path $FlutterSdk 'bin/cache/flutter_tools.snapshot'
    & $dartExecutable $flutterSnapshot build apk --debug --flavor dev --no-pub "--dart-define=CALENDAR_THEME_MODE=$Mode"
    if ($LASTEXITCODE -ne 0) { throw "Calendar $Mode dev debug build failed." }
    $artifactDirectory = Join-Path $repoRoot 'artifacts/calendar_cells_preview'
    New-Item -ItemType Directory -Force -Path $artifactDirectory | Out-Null
    $destination = Join-Path $artifactDirectory "ShiftBell_Calendar_${Mode}_dev_debug.apk"
    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-dev-debug.apk' -Destination $destination -Force
    Get-FileHash -LiteralPath $destination -Algorithm SHA256
} finally {
    Pop-Location
}
