from datetime import datetime
from usb_audit_device import SERIAL,adb,compare_os
from usb_audit_scenarios import scenario
assert SERIAL=='emulator-5556'
for tag,start in [('month','2026-05-31T23:50:00+09:00'),('year','2026-12-31T23:50:00+09:00')]:
 scenario('onetap_'+tag+'_clear','providers/alarm_provider.dart',"final n=AlarmNotifier();try{await n.deleteAllAlarmsCompletely();}finally{n.dispose();}")
 adb('shell','cmd','alarm','set-timezone','Asia/Seoul')
 adb('shell','cmd','alarm','set-time',str(int(datetime.fromisoformat(start).timestamp()*1000)))
 scenario('onetap_'+tag+'_boundary','services/custom_alarm_service.dart',"""
 final now=DateTime.now();final tomorrow=DateTime(now.year,now.month,now.day+1);
 final s=CustomAlarmService.instance;final d=await DatabaseService.instance.database;
 final current='${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';
 check((await s.assign(now,CustomAlarmPreset(time:current,alarmTypeId:3),0)).result==CustomAlarmAssignResult.past,'current minute rejected');
 check((await s.assign(now,const CustomAlarmPreset(time:'00:00',alarmTypeId:3),0)).result==CustomAlarmAssignResult.past,'past today rejected');
 check((await s.assign(DateTime(now.year,now.month,now.day+2),const CustomAlarmPreset(time:'00:00',alarmTypeId:3),0)).result==CustomAlarmAssignResult.outsideWindow,'day after tomorrow rejected');
 check((await d.query('alarms')).isEmpty,'rejections write no alarm');
 final first=await s.assign(tomorrow,const CustomAlarmPreset(time:'00:00',alarmTypeId:3),0);
 final last=await s.assign(tomorrow,const CustomAlarmPreset(time:'23:59',alarmTypeId:3),1);
 check(first.result==CustomAlarmAssignResult.scheduled && last.result==CustomAlarmAssignResult.scheduled,'tomorrow boundaries scheduled');
 check(first.ringAt==tomorrow && last.ringAt==tomorrow.add(const Duration(hours:23,minutes:59)),'month/year changes retain correct date');
 final key='${tomorrow.year}-${tomorrow.month.toString().padLeft(2,'0')}-${tomorrow.day.toString().padLeft(2,'0')}';
 check((await d.query('alarms')).every((r)=>r['assigned_day']==key),'assignment date matches tomorrow');
 """)
 assert compare_os('onetap_'+tag+'_boundary_os')
print('PASS month/year tomorrow00:00/23:59 exact OS targets; past/current/day-after-tomorrow rejected without rows')
