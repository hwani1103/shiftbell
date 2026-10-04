import json,time,xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from usb_audit_device import SERIAL,adb,evaluate,OUT,compare_os,connect_vm
from usb_audit_scenarios import scenario
assert SERIAL=='emulator-5556'
connect_vm()
adb('shell','pm','grant','com.hwani1103.shiftbell.dev','android.permission.POST_NOTIFICATIONS')
scenario('race_clear','providers/alarm_provider.dart',"final n=AlarmNotifier();try{await n.deleteAllAlarmsCompletely();}finally{n.dispose();}")
ident=int(evaluate('race_create','providers/alarm_provider.dart',"(() async {final at=DateTime.now().add(const Duration(seconds:10));final n=AlarmNotifier();try{await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,'0')}:${at.minute.toString().padLeft(2,'0')}',date:at,type:'snoozed',alarmTypeId:3));}finally{n.dispose();}return '${(await (await DatabaseService.instance.database).query('alarms')).single['id']}';})()"))
def ring(tag):
 scenario(tag,'services/database_service.dart',f"var ringing=false;for(var i=0;i<80;i++){{ringing=await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{ident}}})??false;if(ringing)break;await Future<void>.delayed(const Duration(seconds:1));}}check(ringing,'actual OS ring active');",timeout=100)
 values={n.get('name'):n.get('value') for n in ET.fromstring(adb('shell','cat','/data/user_de/0/com.hwani1103.shiftbell.dev/shared_prefs/alarm_state.xml'))}
 assert int(values['currently_ringing_alarm_id'])==ident
 return values['currently_ringing_round']
def action(name,round_):
 result=adb('shell','am','broadcast','-n','com.hwani1103.shiftbell.dev/com.hwani1103.shiftbell.AlarmActionReceiver','-a',name,'--ei','alarmId',str(ident),'--el','ringRound',round_)
 assert b'Broadcast completed' in result
old=ring('race_first_ring');action('SNOOZE_FROM_NOTIFICATION',old)
row=json.loads(evaluate('race_snoozed_row','services/database_service.dart',f"(() async {{return jsonEncode((await (await DatabaseService.instance.database).query('alarms',where:'id=?',whereArgs:[{ident}])).single);}})()"))
adb('shell','cmd','alarm','set-time',str(int(datetime.fromisoformat(row['date']).timestamp()*1000)-5000))
new=ring('race_second_ring');assert new!=old
action('DISMISS_FROM_NOTIFICATION',old);action('SNOOZE_FROM_NOTIFICATION',old)
scenario('race_old_round_ignored','services/database_service.dart',f"final d=await DatabaseService.instance.database;check(await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{ident}}})??false,'old dismiss/snooze leave new round ringing');check((await d.query('alarm_history',where:'alarm_id=?',whereArgs:[{ident}])).length==1,'old actions add no history');")
with ThreadPoolExecutor(max_workers=2) as pool:
 futures=[pool.submit(action,a,new) for a in ['DISMISS_FROM_NOTIFICATION','SNOOZE_FROM_NOTIFICATION']]
 for f in futures:f.result()
scenario('race_first_winner_only','services/database_service.dart',f"final d=await DatabaseService.instance.database;check(!(await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{ident}}})??true),'new round ended');check((await d.query('alarm_history',where:'alarm_id=?',whereArgs:[{ident}])).length==2,'exactly one result per round');final rows=await d.query('alarms',where:'id=?',whereArgs:[{ident}]);check(rows.isEmpty || (rows.length==1 && rows.single['type']=='snoozed'),'dismiss or single snooze winner');")
assert compare_os('race_winner_os')
(OUT/'race_actions.json').write_text(json.dumps({'alarmId':ident,'oldRound':old,'newRound':new,'rootReceiverDelivery':True,'uiButtonTap':False}),encoding='utf-8')
scenario('race_cleanup','providers/alarm_provider.dart',"final n=AlarmNotifier();try{await n.deleteAllAlarmsCompletely();}finally{n.dispose();}")
print('PASS stale notification action round ignored; concurrent current dismiss/snooze produces one result; Native receiver delivery, not UI button taps')
