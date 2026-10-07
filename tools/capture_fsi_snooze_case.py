"""Capture one approved device case. No install, log clear, clock or settings changes.

Never run this before the user connects/authorizes the device. All adb commands
are explicitly serial-scoped. Evidence remains in the local ignored build tree.
"""
import argparse
import datetime
import json
import pathlib
import re
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--case', required=True)
    parser.add_argument('--adb', default=shutil.which('adb') or str(pathlib.Path.home() / 'AppData/Local/Android/sdk/platform-tools/adb.exe'))
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_.:-]+', args.serial) or args.serial.startswith('-'):
        parser.error('Invalid serial')
    if not re.fullmatch(r'[A-Za-z0-9_-]+', args.case):
        parser.error('Case must contain only letters, numbers, underscore or dash')
    stamp = datetime.datetime.now().astimezone().strftime('%Y%m%d_%H%M%S_%f')
    root = pathlib.Path(__file__).resolve().parents[1]
    output = root / 'build' / 'fsi_snooze_samsung' / f'{args.case}_{stamp}'
    output.mkdir(parents=True, exist_ok=False)
    commands = {
        'properties.txt': ['shell', 'getprop'],
        'device_time.txt': ['shell', 'date', '+%Y-%m-%dT%H:%M:%S%z'],
        'dev_package.txt': ['shell', 'dumpsys', 'package', 'com.hwani1103.shiftbell.dev'],
        'dev_appops.txt': ['shell', 'appops', 'get', 'com.hwani1103.shiftbell.dev'],
        'alarmmanager.txt': ['shell', 'dumpsys', 'alarm'],
        'notifications.txt': ['shell', 'dumpsys', 'notification'],
        'window.txt': ['shell', 'dumpsys', 'window'],
        'activity.txt': ['shell', 'dumpsys', 'activity', 'activities'],
        'logcat.txt': ['logcat', '-d', '-v', 'threadtime', 'RingSnooze:I', 'SnoozeFeedback:I', 'NotificationHelper:I',
            'CustomAlarmReceiver:V', 'AlarmActivity:V', 'AlarmOverlay:V', 'AlarmActionHelper:V',
            'AlarmWakeScheduler:V', 'CoverAlarm:V', 'NotifInterruptStateProvider:V', 'ActivityTaskManager:I', '*:S'],
        'screen.png': ['exec-out', 'screencap', '-p'],
    }
    results = {}
    for name, command in commands.items():
        try:
            result = subprocess.run([args.adb, '-s', args.serial, *command], capture_output=True, timeout=35)
            (output / name).write_bytes(result.stdout)
            if result.stderr:
                (output / (name + '.stderr.txt')).write_bytes(result.stderr)
            results[name] = {'exit': result.returncode, 'bytes': len(result.stdout)}
        except (OSError, subprocess.TimeoutExpired) as error:
            results[name] = {'error': str(error)}
    (output / 'capture.json').write_text(json.dumps({'case': args.case, 'serial': args.serial,
        'host_time': stamp, 'status': 'CAPTURE_ONLY_NOT_PASS', 'results': results}, ensure_ascii=False, indent=2), encoding='utf-8')
    print(output)


if __name__ == '__main__':
    main()
