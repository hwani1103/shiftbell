import sys,time,re,xml.etree.ElementTree as ET
from usb_audit_device import adb,capture,tap_text,OUT

def dump():
    adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
    return ET.fromstring(adb('exec-out','cat','/sdcard/usb_audit_ui.xml'))
def bottom():
    adb('shell','input','swipe','540','1800','540','550','550');time.sleep(.4)
def center(node):
    x,y,r,b=map(int,re.findall(r'\d+',node.get('bounds')))
    return str((x+r)//2),str((y+b)//2)
def open_editor():
    tap_text('^편집$');tap_text('^근무명 수정');bottom()
action=sys.argv[1]
open_editor()
if action=='add':
    tap_text('추가');bottom()
    fields=[n for n in dump().iter('node') if n.get('class')=='android.widget.EditText']
    adb('shell','input','tap',*center(fields[-1]))
    adb('shell','input','text','AuditTemp');adb('shell','input','keyevent','KEYCODE_BACK')
elif action=='rename':
    bottom();capture('names_assignment_delete_locked')
    root=dump()
    fields=[n for n in root.iter('node') if n.get('class')=='android.widget.EditText' and n.get('text')=='AuditTemp']
    assert len(fields)==1
    adb('shell','input','tap',*center(fields[0]));adb('shell','input','keycombination','113','29')
    adb('shell','input','text','ExtraTemp');adb('shell','input','keyevent','KEYCODE_BACK')
elif action=='delete':
    bottom();root=dump()
    deletes=[n for n in root.iter('node') if (n.get('text') or n.get('content-desc'))=='삭제']
    adb('shell','input','tap',*center(deletes[-1]))
else:raise ValueError(action)
tap_text('^저장$');capture('names_ui_'+action+'_saved')
