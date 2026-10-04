import json,sys
from datetime import datetime
from usb_audit_device import SERIAL,adb,evaluate,OUT,compare_os
from usb_audit_scenarios import scenario
assert SERIAL=='emulator-5556'
kind=sys.argv[1]
start='2026-11-01T00:30:00-04:00' if kind=='fold' else '2026-03-08T00:30:00-05:00'
wall='01:04' if kind=='fold' else '02:30'
target='2026-11-01T01:04:00-05:00' if kind=='fold' else '2026-03-08T03:30:00-04:00'
epoch=int(datetime.fromisoformat(target).timestamp()*1000)
adb('shell','cmd','alarm','set-timezone','America/New_York')
adb('shell','cmd','alarm','set-time',str(int(datetime.fromisoformat(start).timestamp()*1000)))
scenario('fixed_'+kind+'_prepare','providers/alarm_provider.dart',f"""
 final d=await DatabaseService.instance.database;final n=AlarmNotifier();
 try{{await n.deleteAllAlarmsCompletely();}}finally{{n.dispose();}}
 final now=DateTime.now();
 final s=ShiftSchedule(id:1,isRegular:true,shiftTypes:['Night'],pattern:['Night'],todayIndex:0,startDate:DateTime(now.year,now.month,now.day));
 await DatabaseService.instance.updateShiftSchedule(s);
 await d.insert('shift_alarm_templates',{{'shift_type':'Night','time':'{wall}','alarm_type_id':3,'day_offset':0}});
 await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
 final rows=await d.query('alarms');
 check(rows.any((r)=>Alarm.fromMap(r).date!.millisecondsSinceEpoch=={epoch}),'Native generated expected gap or second-fold epoch');
 """)
assert compare_os('fixed_'+kind+'_native_os')
if kind=='fold':
 first=int(datetime.fromisoformat('2026-11-01T01:04:00-04:00').timestamp()*1000)
 scenario('fixed_fold_add_first_snooze','providers/alarm_provider.dart',f"""
 final n=AlarmNotifier();try{{await n.addAlarm(Alarm(time:'01:04',date:DateTime.fromMillisecondsSinceEpoch({first}),type:'snoozed',alarmTypeId:3));}}finally{{n.dispose();}}
 final d=await DatabaseService.instance.database;final r=await d.query('alarms',where:'time=?',whereArgs:['01:04']);
 check(r.where((r)=>Alarm.fromMap(r).date!.millisecondsSinceEpoch=={first}).length==1,'first occurrence snooze retained');
 check(r.where((r)=>Alarm.fromMap(r).date!.millisecondsSinceEpoch=={epoch}).length==1,'second occurrence fixed retained');
 """)
 assert compare_os('fixed_fold_two_occurrences_os')
 for zone in ['Europe/London','Asia/Seoul','America/New_York']:
  adb('shell','cmd','alarm','set-timezone',zone)
  scenario('snooze_zone_'+zone.replace('/','_'),'services/database_service.dart',f"""
  await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
  final rows=await (await DatabaseService.instance.database).query('alarms',where:'type=?',whereArgs:['snoozed']);
  check(rows.length==1 && DateTime.parse(rows.single['date'] as String).millisecondsSinceEpoch=={first},'timezone change preserves exact snooze instant');
  """)
  assert compare_os('snooze_zone_'+zone.replace('/','_')+'_os')
print('PASS fixed DST',kind)
