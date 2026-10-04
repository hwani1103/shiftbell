from datetime import datetime
from usb_audit_device import SERIAL,adb,compare_os
from usb_audit_scenarios import scenario
assert SERIAL=='emulator-5556'
adb('shell','cmd','alarm','set-timezone','America/New_York')
adb('shell','cmd','alarm','set-time',str(int(datetime.fromisoformat('2026-11-01T00:20:00-04:00').timestamp()*1000)))
scenario('legacy_fold_prepare','providers/alarm_provider.dart',"""
 final n=AlarmNotifier();try{await n.deleteAllAlarmsCompletely();}finally{n.dispose();}
 final d=await DatabaseService.instance.database;
 await d.insert('alarms',{'time':'01:04','date':'2026-11-01T01:04:00.000','type':'snoozed','alarm_type_id':3,'day_offset':0});
 await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
 final r=(await d.query('alarms')).single;
 check(Alarm.fromMap(r).date!.millisecondsSinceEpoch==1793513040000,'legacy offsetless overlap uses compatibility second occurrence, not recovered provenance');
 """)
assert compare_os('legacy_fold_os')
print('PASS legacy offsetless overlap compatibility; first/second provenance is unknowable')
