"""Isolated emulator only. Clock jumps test DST/OS targets, not 300s elapsed time."""
import sys,json,time,xml.etree.ElementTree as ET
from datetime import datetime
from usb_audit_device import SERIAL,adb,evaluate,OUT,compare_os
from usb_audit_scenarios import scenario
assert SERIAL=='emulator-5556', 'Never change the connected user phone clock'
def notification_action(action, ident):
 prefs=ET.fromstring(adb('shell','cat','/data/user_de/0/com.hwani1103.shiftbell.dev/shared_prefs/alarm_state.xml'))
 values={n.get('name'):n.get('value') for n in prefs}
 assert int(values['currently_ringing_alarm_id'])==ident,values
 result=adb('shell','am','broadcast','-n','com.hwani1103.shiftbell.dev/com.hwani1103.shiftbell.AlarmActionReceiver',
     '-a',action,'--ei','alarmId',str(ident),'--el','ringRound',values['currently_ringing_round'])
 assert b'Broadcast completed' in result,result
cases={
 'ny_first':('America/New_York','2026-11-01T00:58:45-04:00',1,4,'-04:00'),
 'ny_fold':('America/New_York','2026-11-01T01:57:45-04:00',1,3,'-05:00'),
 'london_first':('Europe/London','2026-10-25T00:58:45+01:00',1,4,'+01:00'),
 'london_fold':('Europe/London','2026-10-25T01:57:45+01:00',1,3,'+00:00'),
 'ny_gap':('America/New_York','2026-03-08T01:57:45-05:00',3,3,'-04:00'),
}
name=sys.argv[1];zone,start,hour,minute,offset=cases[name]
adb('shell','cmd','alarm','set-timezone',zone)
adb('shell','cmd','alarm','set-time',str(int(datetime.fromisoformat(start).timestamp()*1000)))
scenario(name+'_empty','providers/alarm_provider.dart',"final n=AlarmNotifier();try{await n.deleteAllAlarmsCompletely();}finally{n.dispose();}check((await (await DatabaseService.instance.database).query('alarms')).isEmpty,'isolated fixture cleared');")
ident=int(evaluate(name+'_create','providers/alarm_provider.dart',"""(() async {
 final at=DateTime.now().add(const Duration(seconds:10));final n=AlarmNotifier();
 try{await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,'0')}:${at.minute.toString().padLeft(2,'0')}',date:at,type:'snoozed',alarmTypeId:3));}finally{n.dispose();}
 return '${(await (await DatabaseService.instance.database).query('alarms')).single['id']}';})()""".replace('\n',' ')))
scenario(name+'_ring','services/database_service.dart',f"""
 var ringing=false;for(var i=0;i<100;i++){{ringing=await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{ident}}})??false;if(ringing)break;await Future<void>.delayed(const Duration(seconds:1));}}
 check(ringing,'actual AlarmManager delivery before boundary');
 """,timeout=120)
before=int(adb('shell','date','+%s').decode())*1000
notification_action('SNOOZE_FROM_NOTIFICATION',ident)
time.sleep(1)
row=json.loads(evaluate(name+'_row','services/database_service.dart',f"(() async {{return jsonEncode((await (await DatabaseService.instance.database).query('alarms',where:'id=?',whereArgs:[{ident}])).single);}})()"))
assert row['type']=='snoozed',row
target=datetime.fromisoformat(row['date'])
delta=target.timestamp()*1000-before
assert 300000<=delta<315000,(name,delta,row['date'])
assert target.utcoffset().total_seconds()==datetime.fromisoformat('2000-01-01T00:00:00'+offset).utcoffset().total_seconds(),row
assert target.hour==hour,(name,row)
assert compare_os(name+'_snooze_os')
(OUT/(name+'_result.json')).write_text(json.dumps({'target':row['date'],'delta_from_before_call_ms':delta,'alarmId':ident,'clock_jump':True},indent=2),encoding='utf-8')
adb('shell','cmd','alarm','set-time',str(int(target.timestamp()*1000)-5000))
scenario(name+'_redelivery','services/database_service.dart',f"""
 var ringing=false;for(var i=0;i<100;i++){{ringing=await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{ident}}})??false;if(ringing)break;await Future<void>.delayed(const Duration(seconds:1));}}
 check(ringing,'actual OS redelivery at saved DST target after test clock jump');
 """,timeout=120)
notification_action('DISMISS_FROM_NOTIFICATION',ident)
print('PASS',name,'absolute snooze target, OS reservation and redelivery; elapsed duration not tested here')
