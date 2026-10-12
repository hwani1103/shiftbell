import json
import re
import time
import xml.etree.ElementTree as ET
from usb_audit_device import adb, OUT, capture

fixture=json.loads((OUT/'recents_fixture.json').read_text())
assert int(adb('shell','date','+%s'))*1000 < fixture['epoch']-15000, 'Removal started too late'
removed=0
for _ in range(4):
    adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
    root=ET.fromstring(adb('exec-out','cat','/sdcard/usb_audit_ui.xml'))
    cards=[]
    for node in root.iter('node'):
        if (node.get('text') or node.get('content-desc'))!='교대시계 (테스트)':continue
        x,y,r,b=map(int,re.findall(r'\d+',node.get('bounds')))
        if b-y>500: cards.append((r-x,x,y,r,b))
    if not cards:break
    _,x,y,r,b=max(cards)
    if r-x<400:
        adb('shell','input','swipe','960','1000','400','1000','350')
        time.sleep(.5)
        continue
    adb('shell','input','swipe',str((x+r)//2),str((y+b)//2),str((x+r)//2),'50','250')
    removed+=1
    time.sleep(.5)
else:raise AssertionError('Dev cards still present; other apps were not touched')
assert removed>0
fixture['removed_at_epoch']=int(adb('shell','date','+%s'))*1000
assert fixture['removed_at_epoch'] < fixture['epoch']-5000, 'Removal must finish before delivery'
capture('recents_after_remove')
for i in range(110):
    values={n.get('name'):n.get('value') for n in ET.fromstring(adb('exec-out','run-as','com.hwani1103.shiftbell.dev','cat','/data/user_de/0/com.hwani1103.shiftbell.dev/shared_prefs/alarm_state.xml'))}
    if int(values.get('currently_ringing_alarm_id','-1'))==fixture['id']:
        break
    time.sleep(1)
else:raise AssertionError('No alarm after recents removal')
fixture.update(cards_removed=removed,actual_native_delivery=True,round=int(values['currently_ringing_round']))
(OUT/'recents_result.json').write_text(json.dumps(fixture,indent=2),encoding='utf-8')
adb('shell','run-as','com.hwani1103.shiftbell.dev','/system/bin/am','broadcast','--user','0',
    '-n','com.hwani1103.shiftbell.dev/com.hwani1103.shiftbell.AlarmActionReceiver','-a','DISMISS_FROM_NOTIFICATION',
    '--ei','alarmId',str(fixture['id']),'--el','ringRound',values['currently_ringing_round'])
print('PASS: actual recent-app card removal followed by real native alarm delivery; fixture dismissed.')
