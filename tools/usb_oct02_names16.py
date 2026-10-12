import json,re,sys,xml.etree.ElementTree as ET
from usb_audit_device import adb,tap_text,capture,evaluate,OUT

def fields():
 adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
 return [n for n in ET.fromstring(adb('exec-out','cat','/sdcard/usb_audit_ui.xml')).iter('node') if n.get('class')=='android.widget.EditText']

locale=sys.argv[1]
adb('shell','input','swipe','540','1750','540','650','400')
tap_text('^ ?Add ' if locale=='en' else '^ ?추가 ')
adb('shell','input','swipe','540','1750','540','650','400')
results=[]
for name in ['Night Shift','Afternoon Shift','Sleepover Shift','WWWWWWWWWWWWWWWW','12345678901234567']:
 field=fields()[-1];x,y,r,b=map(int,re.findall(r'\d+',field.get('bounds')))
 adb('shell','input','tap',str((x+r)//2),str((y+b)//2))
 adb('shell','input','keycombination','113','29')
 adb('shell','input','text',name.replace(' ','%s'))
 adb('shell','input','keyevent','KEYCODE_BACK')
 got=fields()[-1].get('text');assert got==name[:16],(name,got)
 results.append({'input':name,'accepted':got,'limit':16})
capture('names16_'+locale+'_input')
tap_text('^Cancel$' if locale=='en' else '^취소$')
(OUT/('names16_'+locale+'_inputs.json')).write_text(json.dumps(results,indent=2),encoding='utf-8')
result=evaluate('names16_'+locale+'_cancel','services/database_service.dart',"(() async {return (await DatabaseService.instance.getShiftSchedule())!.shiftTypes.join(',');})()")
assert result=='주간,야간,오전,오후,휴무,연차'
print('PASS five actual inputs, 16-character boundary and cancellation:',locale)
