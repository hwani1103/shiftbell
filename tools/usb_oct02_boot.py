import sys,json,time,re
from usb_audit_device import evaluate,adb,OUT,compare_os
from usb_audit_scenarios import scenario
action=sys.argv[1]
if action=='prepare':
 ident=int(evaluate('boot_ring_create','providers/alarm_provider.dart',"""(() async {
 final d=await DatabaseService.instance.database;final ids=(await d.query('alarms')).map((r)=>r['id']).toSet();
 final at=DateTime.now().add(const Duration(seconds:8));final n=AlarmNotifier();
 try{await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,"0")}:${at.minute.toString().padLeft(2,"0")}',date:at,type:'custom',alarmTypeId:3));}finally{n.dispose();}
 return '${(await d.query('alarms')).singleWhere((r)=>!ids.contains(r['id']))['id']}';})()""".replace('\n',' ')))
 (OUT/'boot_snooze_id.json').write_text(json.dumps({'id':ident}),encoding='utf-8')
 scenario('boot_actual_ring','services/database_service.dart',f"""
 var on=false;for(var i=0;i<30;i++){{on=await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{ident}}})??false;if(on)break;await Future<void>.delayed(const Duration(seconds:1));}}check(on,'boot fixture actually rings');
 """)
 time.sleep(1);adb('shell','input','tap','720','382');time.sleep(.5)
 raw=evaluate('export_boot_before','services/database_service.dart',"(() async {final d=await DatabaseService.instance.database;return jsonEncode({'alarms':await d.query('alarms',orderBy:'id'),'overrides':await d.query('alarm_overrides',orderBy:'id')});})()")
 (OUT/'boot_before.json').write_text(raw,encoding='utf-8')
 assert any(r['id']==ident and r['type']=='snoozed' for r in json.loads(raw)['alarms'])
 assert compare_os('boot_before_os')
elif action in ['locked','unlocked']:
 dump=adb('shell','dumpsys','alarm').decode('utf-8',errors='replace')
 (OUT/('boot_'+action+'_alarmmanager.txt')).write_text(dump,encoding='utf-8')
 (OUT/('boot_'+action+'_log.txt')).write_bytes(adb('logcat','-d','-s','DirectBoot','AlarmRefreshEngine','DiagLog'))
 (OUT/('boot_'+action+'_window.txt')).write_bytes(adb('shell','dumpsys','window'))
 pattern=r'RTC_WAKEUP #\d+: Alarm\{[^\n]+origWhen (\d+)[^\n]+ com\.hwani1103\.shiftbell\.dev\}\r?\n\s+tag=[^\n]*CustomAlarmReceiver'
 actual=sorted(map(int,re.findall(pattern,dump)))
 expected=json.loads((OUT/'boot_before_os.json').read_text())['expected']
 result={'expected':expected,'actual':actual,'match':actual==expected}
 (OUT/('boot_'+action+'_comparison.json')).write_text(json.dumps(result),encoding='utf-8')
 print('boot',action,'DB-before',len(expected),'OS-after',len(actual),'match',result['match'])
 assert result['match']
else:raise ValueError(action)
