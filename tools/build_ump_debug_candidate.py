"""Build UMP test variants only in an already frozen dev-debug workspace.

No device installation, account changes, production builds, or real ad units.
The UMP hash must be read from the selected test device's SDK log first.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from datetime import datetime
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--candidate', type=Path, required=True,
                        help='Frozen candidate directory containing workspace/ and source_manifest.json')
    parser.add_argument('--app-id', required=True, help='AdMob APPLICATION_ID with a published message')
    parser.add_argument('--device-id', required=True, help='UMP hashed test-device identifier, not ADB serial')
    parser.add_argument('--geography', choices=['eea', 'regulated_us', 'other'], default='eea')
    parser.add_argument('--reset', action='store_true', help='First-choice scenarios only; resets at every process start')
    parser.add_argument('--check-only', action='store_true')
    parser.add_argument('--flutter-sdk', type=Path, default=Path('C:/tools/flutter'))
    args = parser.parse_args()
    candidate = args.candidate.resolve()
    workspace = candidate / 'workspace'
    repo = Path(__file__).resolve().parents[1]
    if workspace == repo or not (candidate / 'source_manifest.json').is_file():
        parser.error('Use a frozen candidate, never the shared working checkout.')
    if not re.fullmatch(r'ca-app-pub-\d{16}~\d{10}', args.app_id):
        parser.error('Invalid AdMob app ID (ad-unit IDs use / and are not app IDs).')
    if args.app_id.startswith('ca-app-pub-3940256099942544'):
        parser.error('Use the app ID whose published UMP message was verified, not the sample app ID.')
    if not re.fullmatch(r'[0-9A-Fa-f]{32}', args.device_id):
        parser.error('Use the 32-hex UMP SDK test identifier from the selected device log.')
    if not args.check_only and set(args.device_id) == {'0'}:
        parser.error('The synthetic validation ID must never be used for an APK build.')
    # Refuse accidental use after product source edits in the frozen workspace.
    manifest = json.loads((candidate / 'source_manifest.json').read_text('utf-8'))['files']
    changed = []
    build_config = {'pubspec.yaml', 'pubspec.lock', 'android/app/build.gradle.kts',
                    'android/build.gradle.kts', 'android/settings.gradle.kts',
                    'android/gradle.properties'}
    for name, expected in manifest.items():
        if name not in build_config and not name.startswith(('lib/', 'android/app/src/', 'assets/', 'data/')):
            continue
        if name.startswith('lib/l10n/generated/'):
            continue
        path = workspace / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            changed.append(name)
    if changed:
        parser.error('Frozen product sources changed; refresh validation first: ' + ', '.join(changed))
    overlay = workspace / 'android/app/src/devDebug/AndroidManifest.xml'
    if overlay.exists():
        parser.error('An existing devDebug manifest needs explicit review; refusing to overwrite it.')
    flavor = (workspace / 'lib/constants/ad_config.dart').read_text('utf-8')
    if "kReleaseMode && appFlavor == 'prod'" not in flavor:
        parser.error('Cannot verify the existing test-ad-unit gate.')
    label = f"ump-{args.geography}-{'reset' if args.reset else 'retain'}"
    output = candidate / f'{label}.apk'
    if output.exists():
        parser.error('Candidate output already exists; preserve it and choose a new candidate directory.')
    command = [str(args.flutter_sdk / 'bin/cache/dart-sdk/bin/dart.exe'),
               str(args.flutter_sdk / 'bin/cache/flutter_tools.snapshot'),
               'build', 'apk', '--debug', '--flavor', 'dev', '--no-pub',
               f'--dart-define=UMP_DEBUG_GEOGRAPHY={args.geography}',
               f'--dart-define=UMP_TEST_DEVICE_IDS={args.device_id.upper()}',
               f"--dart-define=UMP_RESET_CONSENT={'true' if args.reset else 'false'}"]
    if args.check_only:
        print(json.dumps({'validation': 'PASS', 'build': 'NOT_RUN', 'variant': label,
                          'package': 'com.hwani1103.shiftbell.dev', 'test_ad_units': True}))
        return
    xml = ('<manifest xmlns:android="http://schemas.android.com/apk/res/android" '
           'xmlns:tools="http://schemas.android.com/tools"><application>'
           '<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" '
           f'android:value="{args.app_id}" tools:replace="android:value"/>'
           '</application></manifest>\n')
    overlay.parent.mkdir(parents=True, exist_ok=True)
    overlay.write_text(xml, encoding='utf-8')
    try:
        with (candidate / f'{label}.log').open('w', encoding='utf-8') as log:
            subprocess.run(command, cwd=workspace, stdout=log, stderr=subprocess.STDOUT, check=True)
        shutil.copy2(workspace / 'build/app/outputs/flutter-apk/app-dev-debug.apk', output)
        result = {'created': datetime.now().astimezone().isoformat(), 'apk': output.name,
                  'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
                  'type': 'dev debug UMP diagnostic variant', 'geography': args.geography,
                  'reset_each_process': args.reset, 'test_device_id': args.device_id.upper(),
                  'admob_app_id': args.app_id, 'ads': 'Google sample banner unit',
                  'source_manifest': 'source_manifest.json', 'manifest_overlay': xml,
                  'device_tests': 'NOT_RUN', 'installed': False}
        (candidate / f'{label}.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
        print(json.dumps(result))
    finally:
        overlay.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
