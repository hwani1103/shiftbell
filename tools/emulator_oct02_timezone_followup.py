"""Continue from fixed DST fixture; preserve discrepancy before isolating snooze."""
import json
from usb_audit_device import SERIAL,adb,evaluate,compare_os,OUT
from usb_audit_scenarios import scenario
assert SERIAL=='emulator-5556'
evaluate('zone_repeat_refresh','services/database_service.dart',"(() async {return '${await kAlarmChannel.invokeMethod<bool>('forceNativeRefreshAndWait')}';})()")
matches=compare_os('zone_repeat_refresh_os')
(OUT/'timezone_discrepancy_confirmed.txt').write_text(str(not matches),encoding='utf-8')
# Fixture-only cleanup. Do not use this as a proposed production fix.
scenario('timezone_isolate_snooze','services/database_service.dart',"""
 final d=await DatabaseService.instance.database;
 final fixed=await d.query('alarms',where:'type=?',whereArgs:['fixed']);
 await d.transaction((tx)async{await tx.delete('shift_alarm_templates');await tx.delete('alarms',where:'type=?',whereArgs:['fixed']);});
 for(final row in fixed){await kAlarmChannel.invokeMethod('cancelNativeAlarm',{'id':row['id']});}
 check((await d.query('alarms')).length==1,'only absolute snooze fixture remains');
 """)
for zone in ['Europe/London','Asia/Seoul','America/New_York']:
 adb('shell','cmd','alarm','set-timezone',zone)
 scenario('snooze_only_'+zone.replace('/','_'),'services/database_service.dart',"""
 await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
 final rows=await (await DatabaseService.instance.database).query('alarms');
 check(rows.length==1 && Alarm.fromMap(rows.single).date!.millisecondsSinceEpoch==1793509440000,'same first-fold instant remains after timezone change');
 """)
 assert compare_os('snooze_only_'+zone.replace('/','_')+'_os')
print('PASS isolated snooze NY/London/Seoul; mixed fixed discrepancy recorded separately')
