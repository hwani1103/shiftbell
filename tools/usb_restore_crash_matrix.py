"""Actual dev process death at each persisted restore boundary and UI recovery."""
import json
import re
import sqlite3
import subprocess
import time
import xml.etree.ElementTree as ET
from datetime import datetime
from usb_audit_device import ADB, DART, SERIAL, PACKAGE, OUT, ROOT, adb, connect_vm, capture

DB_DIR = '/data/user_de/0/' + PACKAGE + '/databases/'


def verify(name):
    target = OUT / (name + '_db')
    target.mkdir(exist_ok=True)
    for filename in ['shiftbell.db', 'shiftbell.db-wal', 'shiftbell.db-shm']:
        try:
            (target / filename).write_bytes(adb('exec-out', 'run-as', PACKAGE, 'cat', DB_DIR + filename))
        except subprocess.CalledProcessError:
            if filename == 'shiftbell.db': raise
    db = sqlite3.connect(target / 'shiftbell.db')
    assert db.execute('pragma integrity_check').fetchone()[0] == 'ok'
    expected = sorted(int(datetime.fromisoformat(date).timestamp()) * 1000
                      for (date,) in db.execute('select date from alarms')
                      if datetime.fromisoformat(date).timestamp() > time.time())
    db.close()
    dump = adb('shell', 'dumpsys', 'alarm').decode(errors='replace')
    actual = sorted(map(int, re.findall(
        r'RTC_WAKEUP #\d+: Alarm\{[^\n]+origWhen (\d+)[^\n]+ com\.hwani1103\.shiftbell\.dev\}\r?\n\s+tag=[^\n]*CustomAlarmReceiver', dump)))
    result = {'db': len(expected), 'os': len(actual), 'match': expected == actual}
    (OUT / (name + '_match.json')).write_text(json.dumps(result))
    assert result['match'], result
    assert 'job.json' not in adb('shell', 'run-as', PACKAGE, 'ls', DB_DIR + 'restore_work').decode()
    return result


def run_case(phase, recovery, reuse_attach=False):
    name = 'crash_' + phase + '_' + recovery
    print('START', name, flush=True)
    attach = None
    if not reuse_attach:
        log = open(OUT / (name + '_attach.log'), 'wb')
        attach = subprocess.Popen([DART, 'C:/tools/flutter/bin/cache/flutter_tools.snapshot',
            'attach', '-d', SERIAL, '--app-id', PACKAGE], cwd=ROOT, stdout=log,
            stderr=subprocess.STDOUT, stdin=subprocess.PIPE,
            creationflags=subprocess.CREATE_NO_WINDOW)
        deadline = time.time() + 100
        while time.time() < deadline:
            content = (OUT / (name + '_attach.log')).read_bytes()
            if b'Flutter run key commands' in content: break
            if attach.poll() is not None: raise RuntimeError('attach exited')
            time.sleep(1)
        else: raise RuntimeError('attach readiness timeout')
    connect_vm()
    source = (ROOT / 'lib/services/restore_coordinator.dart').read_text(encoding='utf-8').splitlines()
    if phase == 'validated':
        line = next(i + 2 for i, s in enumerate(source) if 'Future<void> _run(RestoreJob' in s)
    else:
        line = next(i + 1 for i, s in enumerate(source) if "DiagLog.log('RESTORE_STEP', {'step': target.name, 'result': 'ok'})" in s)
    config = json.loads((OUT / 'vm.json').read_text())
    config.update(phase=phase, line=line, adb=ADB, serial=SERIAL,
        expression="(() async {final p=BackupPayload.decode(await File('/data/user_de/0/com.hwani1103.shiftbell.dev/files/usb_audit_payload.json').readAsString());await RestoreCoordinator.instance.start(p,overwrite:true);return 'complete';})()")
    path = OUT / (name + '.config.json')
    path.write_text(json.dumps(config))
    result = subprocess.run([DART, str(ROOT / 'tools/usb_restore_crash.dart'), str(path)],
                            capture_output=True, timeout=100)
    (OUT / (name + '.log')).write_bytes(result.stdout + result.stderr)
    if result.returncode: raise RuntimeError(result.stderr.decode(errors='replace'))
    print('KILLED', name, flush=True)
    if attach is not None:
        try: attach.wait(timeout=10)
        except subprocess.TimeoutExpired: attach.terminate()
        log.close()
    adb('shell', 'am', 'start', '-W', '-n', PACKAGE + '/com.hwani1103.shiftbell.MainActivity')
    time.sleep(2)
    capture(name + '_prompt')
    label = 'Continue restoring' if recovery == 'resume' else 'Keep current data'
    nodes = [n for n in ET.parse(OUT / (name + '_prompt.xml')).iter('node')
             if (n.get('text') or n.get('content-desc')) == label]
    assert len(nodes) == 1, 'Missing recovery UI: ' + name
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', nodes[0].get('bounds')))
    adb('shell', 'input', 'tap', str((x1 + x2)//2), str((y1 + y2)//2))
    time.sleep(5)
    verified = verify(name)
    (OUT / (name + '_completed.png')).write_bytes(adb('exec-out', 'screencap', '-p'))
    print('PASS', name, verified, flush=True)


if __name__ == '__main__':
    import sys
    if len(sys.argv) > 1:
        run_case(sys.argv[1], sys.argv[2], '--reuse' in sys.argv)
    else:
        first = True
        for phase in ['validated', 'locked', 'osCleared', 'dbApplied', 'prefsApplied', 'osReconciled']:
            for recovery in ['resume', 'keep']:
                if phase == 'osCleared' and recovery == 'resume': continue  # Already evidenced separately.
                run_case(phase, recovery, reuse_attach=first)
                first = False
