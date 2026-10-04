import json,re,time,xml.etree.ElementTree as ET
from usb_audit_device import adb,tap_text,capture,evaluate,OUT
def fields():
 adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
 return [n for n in ET.fromstring(adb('exec-out','cat','/sdcard/usb_audit_ui.xml')).iter('node') if n.get('class')=='android.widget.EditText']
tap_text('^Add ')
adb('shell','input','swipe','540','1750','540','650','400')
results=[]
for name in ['Day Off','Day Shift','Night duty','Long Day','Twilight','Night Shift','Early Shift','Afternoon Shift']:
 field=fields()[-1];x,y,r,b=map(int,re.findall(r'\d+',field.get('bounds')))
 adb('shell','input','tap',str((x+r)//2),str((y+b)//2))
 adb('shell','input','keycombination','113','29');adb('shell','input','text',name.replace(' ','%s'));adb('shell','input','keyevent','KEYCODE_BACK')
 got=fields()[-1].get('text');assert got==name[:10],(name,got)
 results.append({'input':name,'accepted':got,'limit':10})
capture('english_name_actual_limit')
tap_text('^Cancel$')
(OUT/'english_name_inputs.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
result=evaluate('english_names_cancel_unchanged','services/database_service.dart',"(() async {final s=(await DatabaseService.instance.getShiftSchedule())!;return s.shiftTypes.join(',');})()")
assert result=='주간,야간,오전,오후,휴무,연차'
print('PASS eight real editor inputs; 10 character limit confirmed; cancel preserved original names')
