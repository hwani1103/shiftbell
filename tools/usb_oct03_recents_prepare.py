import json
import time
from usb_audit_device import evaluate, adb, capture, OUT

adb('shell','am','start','-n','com.hwani1103.shiftbell.dev/com.hwani1103.shiftbell.MainActivity')
time.sleep(2)
raw=evaluate('recents_fixture_create','providers/alarm_provider.dart',"""(() async {
  final d=await DatabaseService.instance.database;final ids=(await d.query('alarms')).map((r)=>r['id']).toSet();
  final at=DateTime.now().add(const Duration(seconds:90));final n=AlarmNotifier();
  try{await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,"0")}:${at.minute.toString().padLeft(2,"0")}',date:at,type:'custom',alarmTypeId:3));}finally{n.dispose();}
  final id=(await d.query('alarms')).singleWhere((r)=>!ids.contains(r['id']))['id'];
  return '$id|${at.millisecondsSinceEpoch}';})()""".replace('\n',' '))
ident,epoch=map(int,raw.split('|'))
(OUT/'recents_fixture.json').write_text(json.dumps({'id':ident,'epoch':epoch}),encoding='utf-8')
adb('shell','input','keyevent','KEYCODE_APP_SWITCH')
capture('recents_before_remove')
print('Inspect current dev-app card before swiping; silent test alarm is scheduled.')
