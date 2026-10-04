from datetime import datetime
from usb_audit_device import SERIAL,adb,compare_os
from usb_audit_scenarios import scenario
assert SERIAL=='emulator-5556'
adb('shell','cmd','alarm','set-timezone','Asia/Seoul')
adb('shell','cmd','alarm','set-time',str(int(datetime.fromisoformat('2026-12-30T12:00:00+09:00').timestamp()*1000)))
scenario('offset_year_boundary','providers/alarm_provider.dart',"""
 final n=AlarmNotifier();try{await n.deleteAllAlarmsCompletely();}finally{n.dispose();}
 final d=await DatabaseService.instance.database;await d.delete('alarm_overrides');
 await DatabaseService.instance.updateShiftSchedule(ShiftSchedule(id:1,isRegular:false,shiftTypes:['Night'],assignedDates:{'2027-01-01':'Night'}));
 for(final offset in [-1,0,1]){
 await DatabaseService.instance.replaceAllAlarmTemplates([
 {'shift_type':'Night','time':'00:00','alarm_type_id':3,'day_offset':offset},
 {'shift_type':'Night','time':'23:59','alarm_type_id':3,'day_offset':offset}]);
 await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
 final rows=await d.query('alarms',where:'type=?',whereArgs:['fixed']);
 check(rows.length==2,'two boundary alarms for offset $offset');
 for(final r in rows){
 final date=Alarm.fromMap(r).date!;final target=DateTime(2027,1,1+offset);
 check(date.year==target.year && date.month==target.month && date.day==target.day,'correct actual year/month/day for $offset');
 final assigned=DateTime(date.year,date.month,date.day-offset);
 check(assigned==DateTime(2027,1,1),'fixed date minus offset stays Jan1 for $offset');
 check(r['day_offset']==offset,'offset retained');
 check((date.hour==0 && date.minute==0)||(date.hour==23 && date.minute==59),'00:00 or23:59 intact');
 }
 }
 """)
assert compare_os('offset_year_boundary_os')
print('PASS Native year/month boundary generation for -1/0/+1 x00:00/23:59; UI entry paths not exercised')
