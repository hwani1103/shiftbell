import re,json,xml.etree.ElementTree as ET
from usb_audit_device import adb,tap_text,capture,evaluate,OUT
for index,code in enumerate(['','SB1:old','SB2:','SB2:a/b','SB2:usb_audit_oct02_offline']):
 tap_text('^친구 추가$')
 adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
 root=ET.fromstring(adb('exec-out','cat','/sdcard/usb_audit_ui.xml'))
 field=[n for n in root.iter('node') if n.get('class')=='android.widget.EditText'][-1]
 x,y,r,b=map(int,re.findall(r'\d+',field.get('bounds')))
 adb('shell','input','tap',str((x+r)//2),str((y+b)//2))
 if code:adb('shell','input','text',code)
 adb('shell','input','keyevent','KEYCODE_BACK')
 tap_text('^ ?추가$');capture('friend_invalid_ui_'+str(index))
 value=evaluate('friend_invalid_ui_'+str(index)+'_count','services/database_service.dart',"(() async {final d=await DatabaseService.instance.database;return '${(await d.query(\"friends\")).length}';})()")
 assert value=='1', (code,value)
 text=(OUT/('friend_invalid_ui_'+str(index)+'.xml')).read_text(encoding='utf-8')
 assert '코드' in text and ('올바르' in text or '중복' in text or '이미' in text),code
print('PASS five actual invalid/duplicate add attempts; friend count unchanged')
