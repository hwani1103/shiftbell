"""One bounded USB evidence case: actual app notification +/- clicks and video.
Requires a manually expanded live test notification; never taps other apps.
"""
import subprocess,time,json,re,xml.etree.ElementTree as ET
import fsi_samsung_audit as audit
from usb_audit_device import ADB,SERIAL

before=audit.state()
assert before.get('currently_ringing_alarm_id')=='177',before
remote='/sdcard/fsi_audit_B07_update.mp4'
video=subprocess.Popen([ADB,'-s',SERIAL,'shell','screenrecord','--time-limit','35',remote],
                       stdout=subprocess.PIPE,stderr=subprocess.PIPE)
events=[]
try:
    time.sleep(1)
    for index,button in enumerate(['snoozeIncreaseButton','snoozeIncreaseButton','snoozeDecreaseButton']):
        xmlpath='/sdcard/fsi_audit_B07_'+str(index)+'.xml'
        output=audit.adb('shell','uiautomator','dump',xmlpath,timeout=15).decode()
        assert 'dumped to:' in output,output
        raw=audit.adb('exec-out','cat',xmlpath);audit.adb('shell','rm',xmlpath)
        nodes=[n for n in ET.fromstring(raw).iter('node') if n.get('resource-id')==audit.PACKAGE+':id/'+button]
        assert len(nodes)==1 and nodes[0].get('enabled')=='true'
        x1,y1,x2,y2=map(int,re.findall(r'\d+',nodes[0].get('bounds')))
        event={'button':button,'bounds':nodes[0].get('bounds'),'hostBefore':time.time(),'stateBefore':audit.state()}
        assert event['stateBefore'].get('currently_ringing_alarm_id')=='177'
        audit.adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
        event['stateAfter']=audit.state();events.append(event)
        time.sleep(3)
        audit.shot('B07_update_'+str(index))
    audit.save('B07_update_events.json',events)
finally:
    video.communicate(timeout=40)
    audit.adb('pull',remote,str(audit.OUT/'B07_update.mp4'))
    audit.adb('shell','rm',remote)
    print('Saved bounded notification update video and events',flush=True)
