import json,re,time,xml.etree.ElementTree as ET
from usb_audit_device import adb,tap_text,capture,evaluate,OUT
evaluate('friend_ui_disable_network','services/friend_sync_service.dart','(() async {await FirebaseFirestore.instance.disableNetwork();return "dev Firestore offline";})()')
tap_text('^친구 추가$')
adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
root=ET.fromstring(adb('exec-out','cat','/sdcard/usb_audit_ui.xml'))
for index,value in enumerate(['Oct02Friend','SB2:usb_audit_oct02_offline']):
 adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
 root=ET.fromstring(adb('exec-out','cat','/sdcard/usb_audit_ui.xml'))
 fields=[n for n in root.iter('node') if n.get('class')=='android.widget.EditText']
 field=fields[index]
 x,y,r,b=map(int,re.findall(r'\d+',field.get('bounds')))
 adb('shell','input','tap',str((x+r)//2),str((y+b)//2));adb('shell','input','text',value)
 if index==1:adb('shell','input','keyevent','KEYCODE_BACK')
adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
root=ET.fromstring(adb('exec-out','cat','/sdcard/usb_audit_ui.xml'))
node=next(n for n in root.iter('node') if (n.get('text') or n.get('content-desc'))=='추가')
x,y,r,b=map(int,re.findall(r'\d+',node.get('bounds')))
adb('shell','input','tap',str((x+r)//2),str((y+b)//2));adb('shell','input','tap',str((x+r)//2),str((y+b)//2))
time.sleep(12)
capture('friend_double_add_after')
evaluate('friend_double_ui_count','services/database_service.dart',"(() async {final d=await DatabaseService.instance.database;return '${(await d.query(\"friends\",where:\"owner_id=?\",whereArgs:[\"usb_audit_oct02_offline\"])).length}';})()")
