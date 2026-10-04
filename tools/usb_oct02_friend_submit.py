import re,time,xml.etree.ElementTree as ET
from usb_audit_device import adb,capture,evaluate,OUT
adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
root=ET.fromstring(adb('exec-out','cat','/sdcard/usb_audit_ui.xml'))
node=next(n for n in root.iter('node') if (n.get('text') or n.get('content-desc') or '').strip()=='추가')
x,y,r,b=map(int,re.findall(r'\d+',node.get('bounds')))
adb('shell','input','tap',str((x+r)//2),str((y+b)//2));adb('shell','input','tap',str((x+r)//2),str((y+b)//2))
time.sleep(4)
capture('friend_double_add_after')
count=evaluate('friend_double_ui_count','services/database_service.dart',"(() async {final d=await DatabaseService.instance.database;return '${(await d.query(\"friends\",where:\"owner_id=?\",whereArgs:[\"usb_audit_oct02_offline\"])).length}';})()")
assert count=='1'
root=ET.fromstring((OUT/'friend_double_add_after.xml').read_bytes())
labels=[n.get('text') or n.get('content-desc') or '' for n in root.iter('node')]
print('list remained visible:', '내 일정 공유하기' in labels)
