"""Read-only SRTL device/UMP evidence; requires an explicit TCP ADB serial.

Never installs, clears data, changes settings, folds the device or touches USB.
Run again after launching the dev APK to collect the UMP SDK test-device hash.
"""
import argparse
import json
import re
import subprocess
from datetime import datetime
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--adb', default='C:/Users/Administrator/AppData/Local/Android/sdk/platform-tools/adb.exe')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_.-]+:[0-9]{1,5}', args.serial):
        parser.error('An explicit SRTL host:port serial is required; USB serials are refused.')
    if args.out.exists():
        parser.error('Choose a new evidence filename; existing evidence is preserved.')

    def read(*command):
        result = subprocess.run([args.adb, '-s', args.serial, *command],
                                capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=30)
        return {'exit_code': result.returncode, 'stdout': result.stdout.strip(), 'stderr': result.stderr.strip()}

    state = read('get-state')
    if state['exit_code'] or state['stdout'] != 'device':
        raise SystemExit('Selected SRTL device is not online: ' + json.dumps(state))
    results = {}
    for prop in ['ro.product.model', 'ro.build.version.release', 'ro.build.version.sdk',
                 'ro.build.version.incremental', 'ro.build.fingerprint', 'ro.build.version.oneui']:
        results[prop] = read('shell', 'getprop', prop)
    for name, command in {
        'device_state': ['cmd', 'device_state', 'state'],
        'device_state_help': ['cmd', 'device_state', 'help'],
        'system_locale': ['cmd', 'locale', 'get-device-locale'],
        'app_locale': ['cmd', 'locale', 'get-app-locales', 'com.hwani1103.shiftbell.dev'],
        'timezone': ['getprop', 'persist.sys.timezone'],
        'time_format': ['settings', 'get', 'system', 'time_12_24'],
        'screen_timeout': ['settings', 'get', 'system', 'screen_off_timeout'],
        'stay_on_while_plugged_in': ['settings', 'get', 'global', 'stay_on_while_plugged_in'],
        'dev_package': ['pm', 'path', 'com.hwani1103.shiftbell.dev'],
    }.items():
        results[name] = read('shell', *command)
    results['ump_sdk_log'] = read('logcat', '-d', '-v', 'brief', '-s', 'UserMessagingPlatform')
    sdk_log = results['ump_sdk_log']['stdout']
    hashes = sorted(set(re.findall(r'(?:addTestDeviceHashedId|testDeviceIdentifiers)[^\n]*?[\"\[]([0-9A-Fa-f]{32})', sdk_log)))
    evidence = {'created': datetime.now().astimezone().isoformat(), 'serial': args.serial,
                'read_only': True, 'device_tests': 'NOT_RUN', 'results': results,
                'ump_sdk_hash_candidates': hashes,
                'folding': 'Inspect supported states for this model; do not reuse hardcoded states from another model.'}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'saved': str(args.out), 'model': results['ro.product.model']['stdout'],
                      'ump_sdk_hash_candidates': hashes, 'mutations': 0}))


if __name__ == '__main__':
    main()
