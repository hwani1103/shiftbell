import json,time,re,xml.etree.ElementTree as ET
from usb_audit_device import evaluate,adb,capture,OUT,compare_os

ident=json.loads((OUT/'combined_snooze_id.json').read_text())['id']
expr="(() async {final d=await DatabaseService.instance.database;return jsonEncode({'alarms':await d.query('alarms',orderBy:'id'),'history':await d.query('alarm_history',orderBy:'id')});})()"
before=json.loads(evaluate('export_snooze_double_before','services/database_service.dart',expr))
assert next(r for r in before['alarms'] if r['id']==ident)['type']=='snoozed'
adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
root=ET.fromstring(adb('exec-out','cat','/sdcard/usb_audit_ui.xml'))
node=next(n for n in root.iter('node') if n.get('content-desc')=='Turn Off This Alarm')
x,y,r,b=map(int,re.findall(r'\d+',node.get('bounds')))
adb('shell','input','tap',str((x+r)//2),str((y+b)//2));adb('shell','input','tap',str((x+r)//2),str((y+b)//2))
time.sleep(.5)
after=json.loads(evaluate('export_snooze_double_after','services/database_service.dart',expr))
assert after['alarms']==[r for r in before['alarms'] if r['id']!=ident], 'double tap changed another alarm or snooze still exists'
new=[r for r in after['history'] if r not in before['history']]
assert len(new)==1 and new[0]['alarm_id']==ident, new
assert compare_os('snooze_double_delete_os')
capture('snooze_double_delete_result')
print('PASS: actual snooze delete double tap; other alarms unchanged; one history row')
