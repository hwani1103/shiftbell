import time,json
from datetime import datetime
from usb_audit_device import SERIAL,adb,evaluate,OUT,compare_os
from usb_audit_scenarios import scenario
assert SERIAL=='emulator-5556'
adb('shell','cmd','alarm','set-timezone','Asia/Seoul')
adb('shell','cmd','alarm','set-time',str(int(datetime.fromisoformat('2026-12-31T23:58:00+09:00').timestamp()*1000)))
scenario('year_midnight_complete_prepare','providers/alarm_provider.dart',"""
 final n=AlarmNotifier();try{await n.deleteAllAlarmsCompletely();}finally{n.dispose();}
 final d=await DatabaseService.instance.database;await d.delete('alarm_overrides');
 await DatabaseService.instance.updateShiftSchedule(ShiftSchedule(id:1,isRegular:true,shiftTypes:['Night'],pattern:['Night'],todayIndex:0,startDate:DateTime(2026,12,31)));
 await d.insert('shift_alarm_templates',{'shift_type':'Night','time':'00:05','alarm_type_id':3,'day_offset':0});
 await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
 final fixed=await d.query('alarms',where:'type=?',whereArgs:['fixed'],orderBy:'date');
 final first=fixed.first;
 final a=AlarmNotifier();try{
 await a.deleteAlarm(first['id'] as int,Alarm.fromMap(first).date);
 await a.updateAlarmType(fixed[1]['id'] as int,2);
 await a.addAlarm(Alarm(time:'00:06',date:DateTime(2027,1,1,0,6),type:'custom',alarmTypeId:3));
 await a.addAlarm(Alarm(time:'00:07',date:DateTime(2027,1,1,0,7),type:'snoozed',alarmTypeId:3));
 }finally{a.dispose();}
 final toDelete=AlarmNotifier();try{
 await toDelete.addAlarm(Alarm(time:'00:08',date:DateTime(2027,1,1,0,8),type:'custom',alarmTypeId:3));
 await toDelete.addAlarm(Alarm(time:'00:09',date:DateTime(2027,1,1,0,9),type:'snoozed',alarmTypeId:3));
 for(final r in await d.query('alarms',where:'time IN (?,?)',whereArgs:['00:08','00:09'])){
 await toDelete.deleteAlarm(r['id'] as int,Alarm.fromMap(r).date);
 }
 }finally{toDelete.dispose();}
 await kAlarmChannel.invokeMethod('triggerGuardCheck');
 final overrides=await d.query('alarm_overrides');
 check(overrides.length==2 && overrides.any((r)=>r['action']=='skip') && overrides.any((r)=>r['action']=='set_type'),'both overrides prepared');
 """)
expr="(() async {final d=await DatabaseService.instance.database;return jsonEncode({'alarms':await d.query('alarms',orderBy:'id'),'overrides':await d.query('alarm_overrides')});})()"
before=json.loads(evaluate('year_midnight_complete_before','services/database_service.dart',expr))
assert compare_os('year_midnight_complete_before_os')
adb('shell','cmd','alarm','set-time',str(int(datetime.fromisoformat('2026-12-31T23:59:55+09:00').timestamp()*1000)))
time.sleep(12)
after=json.loads(evaluate('year_midnight_complete_after','services/database_service.dart',expr))
assert before['overrides']==after['overrides']
for row in before['alarms']:assert row in after['alarms'],row
added=[r for r in after['alarms'] if r not in before['alarms']]
assert len(added)==1 and added[0]['date'].startswith('2027-01-10T00:05'),added
assert not any(r['type']=='fixed' and r['date'].startswith('2027-01-01') for r in after['alarms'])
assert not any(r['time'] in ['00:08','00:09'] for r in after['alarms'])
assert compare_os('year_midnight_complete_after_os')
(OUT/'year_midnight_complete_native.log').write_bytes(adb('logcat','-d','-s','AlarmGuardReceiver','AlarmRefreshUtil','AlarmRefreshEngine'))
print('PASS actual year boundary: rolling day10 added once; custom/snooze/skip and original fixed rows retained')

