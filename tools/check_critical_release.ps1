# P0: Run before releasing permission or localization changes. No layout tests.
# -Build: dev debug + web. Add -Release only when explicitly requested by the user.
param([string]$FlutterSdk = 'C:\tools\flutter', [switch]$Build, [switch]$Release)
$ErrorActionPreference = 'Stop'
if ($Release -and -not $Build) { throw '-Release requires -Build and an explicit user request.' }
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
$dartExecutable = Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
$flutterSnapshot = Join-Path $FlutterSdk 'bin/cache/flutter_tools.snapshot'
function Invoke-FlutterChecked {
    # Windows PowerShell 5 turns redirected native stderr warnings into errors.
    # Judge the compiler exit code, while keeping its stderr in the log.
    $savedErrorPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $dartExecutable $flutterSnapshot @args
        $compilerExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedErrorPreference }
    if ($compilerExit -ne 0) { throw "Flutter check failed ($compilerExit): $args" }
}
python tools/generate_korean_only_copy.py
if ($LASTEXITCODE -ne 0) { throw 'Korean-only generation failed' }
python tools/generate_web_locale_assets.py
if ($LASTEXITCODE -ne 0) { throw 'Web locale generation failed' }
node tools/check_web_locale_assets.cjs
if ($LASTEXITCODE -ne 0) { throw 'Web locale checks failed' }
Invoke-FlutterChecked gen-l10n
python tools/audit_l10n_resources.py --output build/critical_resource_audit.json
if ($LASTEXITCODE -ne 0) { throw 'Resource scope audit failed' }
Invoke-FlutterChecked test --no-pub test/permission_state_test.dart test/followup_resource_scope_test.dart test/schedule_reset_scope_test.dart test/third_localization_review_test.dart test/hindi_localization_test.dart test/german_brazilian_release_test.dart test/english_release_copy_test.dart test/default_snooze_setting_test.dart test/one_touch_removal_test.dart test/holiday_overrides_test.dart test/release_audit/g2/my_share_code_pending_banner_test.dart test/release_audit/g2/friend_provider_cache_test.dart test/final_locale_tuning_test.dart test/legacy_work_hours_hint_test.dart
Invoke-FlutterChecked test --no-pub test/work_hours_calendar_days_test.dart test/overtime_calendar_range_test.dart test/regional_release_test.dart test/alarm_dst_test.dart test/timezone_consumed_alarm_test.dart
Push-Location -LiteralPath (Join-Path $projectRoot 'android')
try {
    & .\gradlew.bat :app:testDevDebugUnitTest --tests com.hwani1103.shiftbell.PermissionSettingsTest --tests com.hwani1103.shiftbell.ReleaseLanguagesTest --tests com.hwani1103.shiftbell.NotificationLocaleTest --tests com.hwani1103.shiftbell.G1RingRoundTest --tests com.hwani1103.shiftbell.CoverAlarmNotificationTest --tests com.hwani1103.shiftbell.AlarmDstTest --tests com.hwani1103.shiftbell.TimezoneConsumedAlarmTest --tests com.hwani1103.shiftbell.AlarmRefreshEngineH2Test --tests com.hwani1103.shiftbell.AlarmSnoozeDstTest --tests com.hwani1103.shiftbell.RingSnoozeTest --tests com.hwani1103.shiftbell.SnoozeDefaultsTest --tests com.hwani1103.shiftbell.G1WakeSyncTest --tests com.hwani1103.shiftbell.G6CrossReviewTest --tests com.hwani1103.shiftbell.G6RecheckTest --tests com.hwani1103.shiftbell.EnglishReleaseTest.weekdayOrderAndRemovedFeaturesFollowTheAppLocale --console=plain
    if ($LASTEXITCODE -ne 0) { throw 'Native permission/locale checks failed' }
    & .\gradlew.bat :app:testDevDebugUnitTest --tests com.hwani1103.shiftbell.G0NativeMigrationTest --console=plain
    if ($LASTEXITCODE -ne 0) { throw 'Native DB migration checks failed' }
} finally { Pop-Location }
if ($Build) {
    Invoke-FlutterChecked build apk --debug --flavor dev --no-pub
    if ($Release) { Invoke-FlutterChecked build apk --release --flavor dev --no-pub }
    Invoke-FlutterChecked build web -t lib/web_main.dart --no-pub
}
Write-Output 'P0 automated checks passed. Device permission/locked-alarm checks remain separate.'
