import sys,json,re
from usb_audit_device import evaluate,adb,OUT,PACKAGE,compare_os,connect_vm
from usb_audit_scenarios import scenario
if sys.argv[1]=='prepare':
 connect_vm()
 ident=evaluate('boot_fix_schedule_create','providers/date_schedule_provider.dart',"""(() async {
 final n=DateScheduleNotifier();final at=DateTime.now().add(const Duration(days:1));
 final key='${at.year}-${at.month.toString().padLeft(2,"0")}-${at.day.toString().padLeft(2,"0")}';
 try{final r=await n.create(DateSchedule(date:key,content:'USB direct boot fixture',startMinutes:600,durationMinutes:30,notifyEnabled:true,createdAt:DateTime.now().toIso8601String()));if(!r.notifyScheduled)throw StateError('schedule registration failed');return '${r.saved.id}';}finally{n.dispose();}})()""".replace('\n',' '))
 (OUT/'boot_fix_schedule_id.json').write_text(json.dumps({'id':int(ident)}),encoding='utf-8')
 scenario('boot_fix_delete_all','providers/alarm_provider.dart',"""
 final d=await DatabaseService.instance.database;final h=(await d.query('alarm_history')).length;final n=AlarmNotifier();
 try{await n.deleteAllAlarmsCompletely();}finally{n.dispose();}
 check((await d.query('alarms')).isEmpty,'all wake alarms removed');
 check((await d.query('shift_alarm_templates')).isEmpty,'fixed templates removed');
 check((await d.query('alarm_history')).length>=h,'permanent history retained');
 await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
 check((await d.query('alarms')).isEmpty,'immediate refresh does not resurrect alarms');
 """)
 assert compare_os('boot_fix_deleted_before_os')
else:
 package=adb('shell','cmd','package','list','packages','-U',PACKAGE).decode()
 uid=re.search(r'uid:(\d+)',package).group(1)
 log=adb('logcat','-d','--uid='+uid,'-s','DirectBoot','AlarmRefreshEngine','ScheduleNotification','SleepDetectionScheduler').decode('utf-8',errors='replace')
 (OUT/'boot_fix_dev_log.txt').write_text(log,encoding='utf-8')
 dump=adb('shell','dumpsys','alarm').decode('utf-8',errors='replace')
 (OUT/'boot_fix_alarmmanager.txt').write_text(dump,encoding='utf-8')
 pattern=r'RTC_WAKEUP #\d+: Alarm\{[^\n]+ com\.hwani1103\.shiftbell\.dev\}\r?\n\s+tag=[^\n]*CustomAlarmReceiver'
 assert not re.findall(pattern,dump),'all-delete wake alarm resurrected after boot'
 assert 'credential encrypted storage' not in log,'Direct Boot credential storage exception remains'
 assert log.count('DIRECT BOOT COMPLETE')>=2,'both locked/unlocked boot completion expected'
 sched=r'RTC_WAKEUP #\d+: Alarm\{[^\n]+ com\.hwani1103\.shiftbell\.dev\}\r?\n\s+tag=[^\n]*ScheduleNotificationReceiver'
 assert len(re.findall(sched,dump))==1,'future schedule notification not restored'
 print('PASS: locked/unlocked boot both complete; no CE exception; deleted wake alarms stay absent; one schedule notification restored')
