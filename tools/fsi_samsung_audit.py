"""Local USB Samsung FSI/snooze audit. Explicit serial; dev-only fixtures.

No system clock/timezone changes, no prod mutations, no device data clearing.
Screen/power and dev permission changes are explicit separate commands.
"""
import os
os.environ['SHIFTBELL_AUDIT_OUT'] = 'build/fsi_snooze_samsung_2026-10-06'
os.environ['SHIFTBELL_AUDIT_SERIAL'] = 'R5KL20DHWAE'
os.environ['SHIFTBELL_AUDIT_VM_PORT'] = '58182'
import sys, json, time, re, hashlib, xml.etree.ElementTree as ET
import io, tarfile, sqlite3
sys.stdout.reconfigure(encoding='utf-8')
sys.stderr.reconfigure(encoding='utf-8')
from pathlib import Path
from usb_audit_device import adb, OUT, PACKAGE, connect_vm, evaluate, capture


def save(name, value):
    (OUT/name).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def shell(*args):
    return adb('shell', *args).decode('utf-8', errors='replace').strip()


def state():
    raw = adb('exec-out','run-as',PACKAGE,'cat',f'/data/user_de/0/{PACKAGE}/shared_prefs/alarm_state.xml')
    return {n.get('name'):n.get('value',n.text) for n in ET.fromstring(raw)}


def launch():
    print(shell('am','start','-W','-n',PACKAGE+'/com.hwani1103.shiftbell.MainActivity'))
    time.sleep(1.5)
    connect_vm()


def inspect(name):
    shot(name)
    remote=f'/sdcard/fsi_audit_{int(time.time()*1000)}.xml'
    result=adb('shell','uiautomator','dump',remote,timeout=15).decode(errors='replace')
    if 'dumped to:' not in result: raise RuntimeError('No fresh UI hierarchy: '+result)
    raw=adb('exec-out','cat',remote)
    (OUT/(name+'.xml')).write_bytes(raw)
    adb('shell','rm',remote)
    nodes=list(ET.fromstring(raw).iter('node'))
    print(json.dumps([{'text':n.get('text'),'desc':n.get('content-desc'),'id':n.get('resource-id'),
                      'bounds':n.get('bounds'),'enabled':n.get('enabled'),'checked':n.get('checked')}
                     for n in nodes if n.get('resource-id','').startswith(PACKAGE+':') or
                     (n.get('resource-id')=='android:id/action0' and n.get('text','').startswith('+'))],ensure_ascii=False))
    print('png',OUT/(name+'.png'))


def shot(name):
    raw=adb('exec-out','screencap','-p')
    start=raw.find(b'\x89PNG\r\n\x1a\n');assert start>=0
    (OUT/(name+'.png')).write_bytes(raw[start:])
    data={'host_time':time.time(),'state':state(),'policy':shell('dumpsys','window','policy'),
          'window':shell('dumpsys','window'),'notifications':shell('dumpsys','notification'),
          'alarmmanager':shell('dumpsys','alarm')}
    save(name+'_evidence.json',data)
    (OUT/(name+'_logcat.txt')).write_bytes(adb('logcat','-d','-v','threadtime','RingSnooze:V','AlarmActivity:V',
        'AlarmOverlay:V','AlarmActionHelper:V','AlarmAction:V','AlarmPlayer:V','CustomAlarmReceiver:V',
        'NotificationHelper:V','RingDeadline:V','RingingAlarmTracker:V','InAppAlarm:V',
        'ActivityTaskManager:I','NotifInterruptStateProvider:V','*:S'))
    print(name,'state',data['state'].get('currently_ringing_alarm_id'),data['state'].get('ring_snooze_minutes'))


def tables(name):
    text=evaluate('export_'+name,'services/database_service.dart',"""(() async {
      final d=await DatabaseService.instance.database;
      final names=await d.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
      final data=<String,dynamic>{};
      for(final t in names){final n=t['name'] as String;data[n]=await d.query(n,orderBy:'rowid');}
      return jsonEncode(data);
    })()""".replace('\n',' '))
    save(name+'.json',json.loads(text))


def db_snapshot(name):
    """Read-only device copy; only the local SQLite copy may recover its WAL."""
    destination=OUT/(name+'_db');destination.mkdir(exist_ok=True)
    raw=adb('exec-out','run-as',PACKAGE,'tar','-C',f'/data/user_de/0/{PACKAGE}/databases',
            '-cf','-','shiftbell.db','shiftbell.db-wal')
    with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
        for member in archive.getmembers():
            if member.name in ['shiftbell.db','shiftbell.db-wal']:
                (destination/member.name).write_bytes(archive.extractfile(member).read())
    connection=sqlite3.connect(destination/'shiftbell.db');connection.row_factory=sqlite3.Row
    try:
        assert connection.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
        data={table:[dict(row) for row in connection.execute('SELECT * FROM '+table)]
              for table in ['alarms','alarm_history','alarm_creation_log','alarm_types']}
    finally:connection.close()
    save(name+'.json',data)
    return data


def main():
    command=sys.argv[1]
    if command=='baseline':
        baseline={}
        commands={
          'zone':['getprop','persist.sys.timezone'], 'auto_time':['settings','get','global','auto_time'],
          'auto_zone':['settings','get','global','auto_time_zone'], 'stay':['settings','get','global','stay_on_while_plugged_in'],
          'font_scale':['settings','get','system','font_scale'], 'screen_timeout':['settings','get','system','screen_off_timeout'],
          'locales':['cmd','locale','get-app-locales',PACKAGE], 'appops':['cmd','appops','get',PACKAGE],
          'package':['dumpsys','package',PACKAGE], 'power':['dumpsys','power'],
          'device_time':['date','+%Y-%m-%dT%H:%M:%S%z'], 'alarmmanager':['dumpsys','alarm'],
          'notifications':['dumpsys','notification'], 'window':['dumpsys','window'],
          'trust':['dumpsys','trust'], 'uimode':['cmd','uimode','night'],
          'accessibility':['settings','get','secure','enabled_accessibility_services'],
        }
        for name,args in commands.items():
            baseline[name]=shell(*args)
        save('baseline_device.json',baseline)
        for location in ['user','user_de']:
            (OUT/('baseline_'+location+'.tar')).write_bytes(adb('exec-out','run-as',PACKAGE,'tar','-C',f'/data/{location}/0/{PACKAGE}','-cf','-','.'))
        apk=shell('pm','path',PACKAGE).removeprefix('package:').splitlines()[0]
        adb('pull',apk,str(OUT/'installed_before.apk'))
        print('Saved baseline and dev data; installed APK SHA256',hashlib.sha256((OUT/'installed_before.apk').read_bytes()).hexdigest())
        print({key:baseline[key] for key in ['zone','auto_time','auto_zone','stay','locales','font_scale']})
    elif command=='launch': launch()
    elif command=='ui': inspect(sys.argv[2])
    elif command=='shot': shot(sys.argv[2])
    elif command=='tables': tables(sys.argv[2])
    elif command=='dbrows':
        print(db_snapshot(sys.argv[2])['alarms'])
    elif command=='permissions':
        print(evaluate(sys.argv[2],'services/database_service.dart',"(() async => jsonEncode(await kAlarmChannel.invokeMethod('permissionSnapshot')))()"))
    elif command=='state':
        value=state();save(sys.argv[2]+'.json',value);print(value)
    elif command in ['arm','arm_at']:
        case=sys.argv[2];delay=int(sys.argv[3])
        assert re.fullmatch(r'[A-Za-z0-9_]+',case)
        if command=='arm':
            assert 5<=delay<=2100
            target_expression='((DateTime.now().millisecondsSinceEpoch+DELAY*1000)~/1000+1)*1000'.replace('DELAY',str(delay))
        else:
            assert time.time()*1000+4000 <= delay <= time.time()*1000+2100000
            target_expression=str(delay)
        expression="""(() async {
          final d=await DatabaseService.instance.database;
          final types=await d.query('alarm_types',where:'id = ?',whereArgs:[3]);
          if(types.single['sound_file']!='silent' || types.single['vibration_strength']!=0) throw StateError('Not silent');
          final label='FSI26 CASE';
          if((await d.query('alarms',where:'shift_type = ?',whereArgs:[label])).isNotEmpty) throw StateError('Fixture already exists');
          final at=DateTime.fromMillisecondsSinceEpoch(TARGET_EXPRESSION);
          final n=AlarmNotifier();
          try {await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,"0")}:${at.minute.toString().padLeft(2,"0")}',date:at,type:'custom',alarmTypeId:3,shiftType:label));}
          finally{n.dispose();}
          final row=(await d.query('alarms',where:'shift_type = ?',whereArgs:[label])).single;
          return '${row['id']}|${at.millisecondsSinceEpoch}';
        })()""".replace('CASE',case).replace('TARGET_EXPRESSION',target_expression).replace('\n',' ')
        ident,target=evaluate(case+'_arm','providers/alarm_provider.dart',expression).split('|')
        value={'case':case,'id':int(ident),'target':int(target),'label':'FSI26 '+case,'typeId':3}
        save(case+'_fixture.json',value)
    elif command=='rows':
        text=evaluate('export_'+sys.argv[2],'services/database_service.dart',"""(() async {
          final d=await DatabaseService.instance.database;
          return jsonEncode({'alarms':await d.query('alarms'),'history':await d.query('alarm_history',where:'shift_type LIKE ?',whereArgs:['FSI26 %']),'creation':await d.query('alarm_creation_log',where:'shift_type LIKE ?',whereArgs:['FSI26 %'])});
        })()""".replace('\n',' '))
        save(sys.argv[2]+'.json',json.loads(text))
        print('alarms',json.loads(text)['alarms'])
    elif command=='register_snooze':
        minutes=int(sys.argv[2]);case=sys.argv[3];surface=sys.argv[4]
        fixture=json.loads((OUT/(case+'_fixture.json')).read_text(encoding='utf-8'))
        ident=int(fixture['id'])
        log=adb('logcat','-d','-v','threadtime','RingSnooze:I','*:S').decode('utf-8',errors='replace')
        pattern=rf'EXECUTE id={ident} round=(\d+) minutes={minutes} revision=(\d+) accepted=(\d+) target=(\d+) elapsed=(\d+) result=(\w+)'
        match=list(re.finditer(pattern,log))[-1]
        oldround,revision,accepted,target,elapsed=map(int,match.groups()[:5])
        assert match.group(6)=='Scheduled',match.group(0)
        assert target==((accepted+minutes*60000+999)//1000)*1000
        row=next(row for row in db_snapshot(case+'_registered')['alarms'] if row['id']==ident)
        from datetime import datetime
        assert int(datetime.fromisoformat(row['date']).timestamp())*1000==target,row
        dump=shell('dumpsys','alarm')
        targets=re.findall(r'RTC_WAKEUP #\d+: Alarm\{[^\n]+origWhen (\d+)[^\n]+ com\.hwani1103\.shiftbell\.dev\}',dump)
        assert str(target) in targets,(target,targets)
        existing=json.loads((OUT/'natural_cases.json').read_text(encoding='utf-8')) if (OUT/'natural_cases.json').exists() else {}
        existing[str(minutes)]={'id':ident,'fixture':case,'minutes':minutes,'surface':surface,'sourceRound':oldround,
            'revision':revision,'accepted':accepted,'target':target,'processingMs':elapsed,'db':row,'status':'SCHEDULED_NOT_YET_NATURAL_PASS'}
        save('natural_cases.json',existing)
        (OUT/(case+'_registered_alarmmanager.txt')).write_text(dump,encoding='utf-8')
        print(existing[str(minutes)])
    elif command=='watch':
        # Read-only bounded observer; no input, setting changes, or mutations.
        end=time.monotonic()+min(int(sys.argv[2]),7200)
        observed=OUT/'natural_observations';observed.mkdir(exist_ok=True)
        print('Read-only natural observer started',flush=True)
        while time.monotonic()<end:
            try:
                manifest=OUT/'natural_cases.json'
                cases=json.loads(manifest.read_text(encoding='utf-8')) if manifest.exists() else {}
                current=state()
                for minutes,case in cases.items():
                    if (observed/(minutes+'.json')).exists():continue
                    if (str(case['id'])==current.get('currently_ringing_alarm_id') and
                        int(current.get('currently_ringing_round','-1'))!=case['sourceRound'] and
                        time.time()*1000>=case['target']):
                        name='auto_N'+minutes+'_round'+current['currently_ringing_round']
                        shot(name)
                        (observed/(minutes+'.json')).write_text(json.dumps({'status':'CAPTURED_PENDING_REVIEW',
                            'case':case,'state':current,'evidence':name,'captured':time.time()},indent=2),encoding='utf-8')
                        print('Captured',minutes,name,flush=True)
            except Exception as error: print(type(error).__name__,str(error)[:300],flush=True)
            time.sleep(2)
        print('Read-only observer finished',flush=True)
    elif command=='cleanup_case':
        case=sys.argv[2]
        fixture=json.loads((OUT/(case+'_fixture.json')).read_text(encoding='utf-8'))
        ident=int(fixture['id'])
        expression="""(() async {
          final d=await DatabaseService.instance.database;
          final rows=await d.query('alarms',where:'id = ?',whereArgs:[IDENT]);
          if(rows.isEmpty)return 'already ended';
          if(rows.single['shift_type']!='FSI26 CASE')throw StateError('Unowned alarm');
          final alarm=Alarm.fromMap(rows.single);final n=AlarmNotifier();
          try {await n.deleteAlarm(IDENT,alarm.date);}finally{n.dispose();}
          return 'fixture removed';
        })()""".replace('IDENT',str(ident)).replace('CASE',case).replace('\n',' ')
        print(evaluate(case+'_cleanup','providers/alarm_provider.dart',expression))
    elif command=='duration':
        minutes=int(sys.argv[2]);assert minutes in [1,3]
        expression="""(() async {
          final d=await DatabaseService.instance.database;
          final old=(await d.query('alarm_types',where:'id = ?',whereArgs:[3])).single;
          if(old['sound_file']!='silent'||old['vibration_strength']!=0)throw StateError('Not silent');
          await d.update('alarm_types',{'duration':MINUTES},where:'id = ?',whereArgs:[3]);
          return jsonEncode({'before':old,'after':(await d.query('alarm_types',where:'id = ?',whereArgs:[3])).single});
        })()""".replace('MINUTES',str(minutes)).replace('\n',' ')
        value=json.loads(evaluate('duration_'+str(minutes),'services/database_service.dart',expression))
        save('duration_'+str(minutes)+'.json',value)
    elif command=='eval':
        print(evaluate(sys.argv[2],sys.argv[3],Path(sys.argv[4]).read_text(encoding='utf-8').replace('\n',' ')))
    elif command=='tap':
        name,field,value=sys.argv[2:5]
        if field not in ['resource-id','text','content-desc']: raise ValueError('Unsupported UI field')
        remote=f'/sdcard/fsi_audit_{int(time.time()*1000)}.xml'
        output=adb('shell','uiautomator','dump',remote,timeout=15).decode(errors='replace')
        if 'dumped to:' not in output: raise RuntimeError('No fresh UI hierarchy: '+output)
        raw=adb('exec-out','cat',remote)
        adb('shell','rm',remote)
        nodes=[n for n in ET.fromstring(raw).iter('node') if n.get(field)==value]
        assert len(nodes)==1,[(n.get('text'),n.get('bounds')) for n in nodes]
        n=nodes[0];assert n.get('enabled')=='true', 'Button disabled'
        x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')))
        before=int(shell('date','+%s'))*1000
        adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
        save(name+'_tap.json',{'before_second':before,'field':field,'value':value,'bounds':n.get('bounds')})
        time.sleep(.4)
        print(name,'tapped',value)
    else: raise ValueError(command)


if __name__=='__main__':main()
