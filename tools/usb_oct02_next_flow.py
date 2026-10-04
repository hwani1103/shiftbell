import json,time,re,sys,xml.etree.ElementTree as ET
from usb_audit_device import adb,evaluate,tap_text,capture,OUT,compare_os
ident=int((OUT/'next_extra_id.json').read_text())
prefix='next_snooze_flow_' if len(sys.argv)>1 else 'next_flow_'
def state(label):
 return json.loads(evaluate('export_'+prefix+label,'screens/settings_tab.dart',"(() async {final d=await DatabaseService.instance.database;return jsonEncode({'alarms':await d.query('alarms',orderBy:'id'),'history':await d.query('alarm_history',orderBy:'id'),'overrides':await d.query('alarm_overrides'),'presets':(await SharedPreferences.getInstance()).getString('custom_alarm_presets')});})()"))
before=state('before');original=[r for r in before['alarms'] if r['id']!=ident]
for kind,label in ([] if len(sys.argv)>1 else [(2,'진동'),(3,'무음'),(1,'소리\+진동')]):
 tap_text('^'+label+'$')
 tap_text('^달력');tap_text('^다음알람');time.sleep(.5)
 now=state('type_'+str(kind))
 assert next(r for r in now['alarms'] if r['id']==ident)['alarm_type_id']==kind
 assert [r for r in now['alarms'] if r['id']!=ident]==original
 assert now['presets']==before['presets'] and now['overrides']==before['overrides']
 capture(prefix+'type_'+str(kind))
baseline=state('cancel_before')
tap_text('^이 알람 끄기$');capture(prefix+'delete_prompt');tap_text('^취소$')
tap_text('^달력');tap_text('^다음알람')
assert state('cancel_after')==baseline
assert compare_os(prefix+'cancel_os')
tap_text('^이 알람 끄기$')
adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
nodes=[n for n in ET.fromstring(adb('exec-out','cat','/sdcard/usb_audit_ui.xml')).iter('node') if (n.get('text') or n.get('content-desc'))=='삭제']
assert len(nodes)==1
x,y,r,b=map(int,re.findall(r'\d+',nodes[0].get('bounds')))
adb('shell','input','tap',str((x+r)//2),str((y+b)//2));adb('shell','input','tap',str((x+r)//2),str((y+b)//2))
after=state('deleted')
assert after['alarms']==original
added=[r for r in after['history'] if r not in baseline['history']]
assert len(added)==1 and added[0]['alarm_id']==ident
assert compare_os(prefix+'final_os')
print('PASS actual custom type changes/reentry; cancel preserves all; double deletion retains other alarm with one history')
