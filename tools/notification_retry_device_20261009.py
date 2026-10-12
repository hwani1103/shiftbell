"""Bounded USB checks for notification-first external alarm presentation (dev only)."""
import os
os.environ['SHIFTBELL_AUDIT_OUT'] = 'artifacts/notification_retry_2026_10_09'
os.environ['SHIFTBELL_AUDIT_SERIAL'] = 'R5KL20DHWAE'
os.environ['SHIFTBELL_AUDIT_VM_PORT'] = '58190'
import sys, json, time, re, pathlib, xml.etree.ElementTree as ET
from usb_audit_device import adb, OUT, PACKAGE, connect_vm, evaluate
sys.stdout.reconfigure(encoding='utf-8')

def shell(*args):
    return adb('shell', *args).decode('utf-8', 'replace').strip()

def save(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

def state():
    raw = adb('exec-out', 'run-as', PACKAGE, 'cat', f'/data/user_de/0/{PACKAGE}/shared_prefs/alarm_state.xml')
    return {n.get('name'): n.get('value', n.text) for n in ET.fromstring(raw)}

def ui(name):
    raw = adb('exec-out', 'screencap', '-p')
    (OUT / (name + '.png')).write_bytes(raw[raw.index(b'\x89PNG\r\n\x1a\n'):])
    remote = '/sdcard/notification_priority_ui.xml'
    shell('uiautomator', 'dump', remote)
    raw = adb('exec-out', 'cat', remote)
    (OUT / (name + '.xml')).write_bytes(raw)
    shell('rm', remote)
    nodes = list(ET.fromstring(raw).iter('node'))
    print(json.dumps([{'text': n.get('text'), 'desc': n.get('content-desc'),
                      'id': n.get('resource-id'), 'bounds': n.get('bounds')}
                     for n in nodes if n.get('text') or n.get('content-desc')], ensure_ascii=False))
    return nodes

def snapshot(name):
    save(name + '_state.json', state())
    for label, args in {'window': ['dumpsys', 'window'], 'notification': ['dumpsys', 'notification', '--noredact'],
                        'alarm': ['dumpsys', 'alarm'], 'policy': ['dumpsys', 'window', 'policy']}.items():
        (OUT / (name + '_' + label + '.txt')).write_text(shell(*args), encoding='utf-8')
    (OUT / (name + '_logcat.txt')).write_bytes(adb('logcat', '-d', '-v', 'threadtime',
        'CustomAlarmReceiver:V', 'NotificationHelper:V', 'RingControlPresence:V', 'AlarmOverlay:V',
        'AlarmActivity:V', 'RingSnooze:V', 'AlarmActionHelper:V', 'AlarmPlayer:V', 'RingDeadline:V', '*:S'))
    try:
        ui(name)
    except Exception as error:
        # Secure lock screens can deny/timeout accessibility dumps; retain raw OS evidence.
        save(name + '_ui_error.json', {'error': str(error), 'ui_verified': False})
        print('UI hierarchy unavailable; OS evidence retained:', error)

def tables(name):
    data = evaluate('export_' + name, 'services/database_service.dart', """(() async {
      final d=await DatabaseService.instance.database;
      final names=await d.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
      final data=<String,dynamic>{};
      for(final t in names){final n=t['name'] as String;data[n]=await d.query(n,orderBy:'rowid');}
      return jsonEncode(data);})()""".replace('\n', ' '))
    save(name + '.json', json.loads(data))

def arm(case, delay):
    assert re.fullmatch(r'[a-zA-Z0-9_]+', case)
    assert 10 <= delay <= 120
    expr = """(() async {
      final d=await DatabaseService.instance.database;
      final t=(await d.query('alarm_types',where:'id = ?',whereArgs:[3])).single;
      if(t['sound_file']!='silent'||t['vibration_strength']!=0)throw StateError('Not silent');
      final label='NR09 CASE';
      if((await d.query('alarms',where:'shift_type = ?',whereArgs:[label])).isNotEmpty)throw StateError('Duplicate fixture');
      final at=DateTime.fromMillisecondsSinceEpoch(((DateTime.now().millisecondsSinceEpoch+DELAY*1000)~/1000+1)*1000);
      final n=AlarmNotifier();
      try {await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,"0")}:${at.minute.toString().padLeft(2,"0")}',date:at,type:'custom',alarmTypeId:3,shiftType:label));}
      finally {n.dispose();}
      final row=(await d.query('alarms',where:'shift_type = ?',whereArgs:[label])).single;
      return '${row['id']}|${at.millisecondsSinceEpoch}';})()""".replace('CASE', case).replace('DELAY', str(delay)).replace('\n', ' ')
    ident, target = evaluate(case + '_arm', 'providers/alarm_provider.dart', expr).split('|')
    save(case + '_fixture.json', {'id': int(ident), 'target': int(target), 'label': 'NR09 ' + case})

def main():
    command = sys.argv[1]
    if command == 'launch':
        print(shell('am', 'start', '-W', '-n', PACKAGE + '/com.hwani1103.shiftbell.MainActivity'))
        time.sleep(2)
        connect_vm()
    elif command == 'arm': arm(sys.argv[2], int(sys.argv[3]))
    elif command == 'snapshot': snapshot(sys.argv[2])
    elif command == 'ui': ui(sys.argv[2])
    elif command == 'tables': tables(sys.argv[2])
    elif command == 'state': print(state())
    elif command == 'permission':
        print(evaluate(sys.argv[2], 'services/database_service.dart', "(() async => jsonEncode(await kAlarmChannel.invokeMethod('permissionSnapshot')))()"))
    elif command == 'tap':
        name, field, value = sys.argv[2:5]
        nodes = [n for n in ui(name + '_before_tap') if n.get(field) == value and n.get('enabled') == 'true']
        assert len(nodes) == 1, [(n.get('text'), n.get('bounds')) for n in nodes]
        x1,y1,x2,y2 = map(int, re.findall(r'\d+', nodes[0].get('bounds')))
        shell('input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
        save(name + '_tap.json', {'field':field,'value':value,'bounds':nodes[0].get('bounds')})
    elif command == 'cleanup':
        expr = """(() async {
          final d=await DatabaseService.instance.database;
          final rows=await d.query('alarms',where:'shift_type LIKE ?',whereArgs:['NR09 %']);
          final n=AlarmNotifier();
          try {for(final r in rows){final a=Alarm.fromMap(r);await n.deleteAlarm(a.id!,a.date);}}
          finally {n.dispose();}
          return 'removed ${rows.length} owned alarms';})()""".replace('\n', ' ')
        print(evaluate('cleanup', 'providers/alarm_provider.dart', expr))
    elif command == 'eval':
        print(evaluate(sys.argv[2], sys.argv[3], pathlib.Path(sys.argv[4]).read_text(encoding='utf-8').replace('\n',' ')))
    else: raise ValueError(command)

if __name__ == '__main__': main()
