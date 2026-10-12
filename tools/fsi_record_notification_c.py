"""Bounded actual UI regression video; explicit USB dev fixture only."""
import subprocess,time,re,json,sys,xml.etree.ElementTree as ET
import fsi_samsung_audit as a
from usb_audit_device import ADB,SERIAL
ident=sys.argv[1]; prefix=sys.argv[2]
assert re.fullmatch(r"C[A-Za-z0-9_]+",prefix)
assert a.state().get('currently_ringing_alarm_id')==ident
remote='/sdcard/fsi_audit_'+prefix+'.mp4'
video=subprocess.Popen([ADB,'-s',SERIAL,'shell','screenrecord','--time-limit','35',remote],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
events=[]
try:
 for index,button in enumerate(['snoozeIncreaseButton','snoozeIncreaseButton','snoozeDecreaseButton']):
  path='/sdcard/fsi_audit_'+prefix+'_'+str(index)+'.xml'
  output=a.adb('shell','uiautomator','dump',path,timeout=15).decode()
  assert 'dumped to:' in output,output
  raw=a.adb('exec-out','cat',path);a.adb('shell','rm',path)
  (a.OUT/(prefix+'_'+str(index)+'.xml')).write_bytes(raw)
  nodes=[n for n in ET.fromstring(raw).iter('node') if n.get('resource-id')==a.PACKAGE+':id/'+button]
  assert len(nodes)==1 and nodes[0].get('enabled')=='true',[(n.get('resource-id'),n.get('bounds')) for n in nodes]
  x1,y1,x2,y2=map(int,re.findall(r'\d+',nodes[0].get('bounds')))
  event={'button':button,'bounds':nodes[0].get('bounds'),'at':time.time(),'before':a.state()}
  assert event['before'].get('currently_ringing_alarm_id')==ident
  a.adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));time.sleep(2)
  event['after']=a.state();events.append(event)
  a.shot(prefix+'_'+str(index))
finally:
 a.save(prefix+'_events.json',events)
 video.communicate(timeout=40)
 a.adb('pull',remote,str(a.OUT/(prefix+'.mp4')));a.adb('shell','rm',remote)
 print('Saved',prefix,flush=True)
