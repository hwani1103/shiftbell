import json,time,re,xml.etree.ElementTree as ET
from usb_audit_device import evaluate,OUT,adb,compare_os,capture,tap_text
ident=json.loads((OUT/'date_fixed_fixture.json').read_text())['id']
expr="(() async {final d=await DatabaseService.instance.database;return jsonEncode({'alarms':await d.query('alarms',orderBy:'id'),'history':await d.query('alarm_history',orderBy:'id'),'overrides':await d.query('alarm_overrides')});})()"
before=json.loads(evaluate('export_date_double_before','services/database_service.dart',expr))
tap_text('^삭제$')
adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
nodes=[n for n in ET.fromstring(adb('exec-out','cat','/sdcard/usb_audit_ui.xml')).iter('node') if (n.get('text') or n.get('content-desc'))=='삭제']
assert len(nodes)==1
x,y,r,b=map(int,re.findall(r'\d+',nodes[0].get('bounds')))
adb('shell','input','tap',str((x+r)//2),str((y+b)//2));adb('shell','input','tap',str((x+r)//2),str((y+b)//2))
time.sleep(.6)
after=json.loads(evaluate('export_date_double_after','services/database_service.dart',expr))
assert after['alarms']==[r for r in before['alarms'] if r['id']!=ident]
history=[r for r in after['history'] if r not in before['history']]
assert len(history)==1 and history[0]['alarm_id']==ident
assert len(after['overrides'])==1 and after['overrides'][0]['action']=='skip'
assert compare_os('date_double_delete_os')
capture('date_double_deleted')
print('PASS actual date-popup double deletion: one target, one history, skip override, other reservations retained')
