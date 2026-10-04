"""Actual SRTL OS delivery and native alarm controls; no clock acceleration."""
import json,re,sys,time,io,xml.etree.ElementTree as ET
from usb_audit_device import adb,evaluate,capture,connect_vm,OUT,PACKAGE,SERIAL,compare_os
from usb_audit_scenarios import scenario

assert SERIAL.startswith('localhost:')
def native_state():
    root=ET.fromstring(adb('exec-out','run-as',PACKAGE,'cat','/data/user_de/0/'+PACKAGE+'/shared_prefs/alarm_state.xml'))
    return {n.get('name'):n.get('value',n.text) for n in root}

def ui():
    adb('shell','uiautomator','dump','/sdcard/srtl_ring_ui.xml')
    return adb('exec-out','cat','/sdcard/srtl_ring_ui.xml')

def action_point(name):
    root=ET.fromstring(ui()); nodes=[n for n in root.iter('node') if (n.get('resource-id') or '').endswith('/'+name+'Button')]
    if len(nodes)==1:
        x,y,r,b=map(int,re.findall(r'\d+',nodes[0].get('bounds')))
        return (x+r)//2,(y+b)//2
    # Samsung's non-focusable application overlay is absent from the default
    # UIAutomator tree. Locate its two native circle buttons in actual pixels.
    from PIL import Image
    data=adb('exec-out','screencap','-p');data=data[data.index(b'\x89PNG\r\n\x1a\n'):]
    im=Image.open(io.BytesIO(data)).convert('RGB');w,h=im.size
    scale=4
    region=im.crop((w//2,0,w,h)).resize((max(1,w//2//scale),h//scale))
    colors=region.getcolors(region.width*region.height)
    candidates=[(count,c) for count,c in colors if 60<c[0]<160 and 30<c[1]<135 and c[2]>c[0]*1.4 and c[2]>c[1]*1.8]
    if not candidates:raise RuntimeError('Native action absent from XML and screenshot')
    count,color=max(candidates)
    rw=region.width
    points={i for i,c in enumerate(region.getdata()) if c==color}
    circles=[]
    while points:
        first=points.pop();todo=[first];component=[first]
        while todo:
            p=todo.pop()
            for q in [p-rw,p+rw,p-1,p+1]:
                if q in points:
                    points.remove(q);todo.append(q);component.append(q)
        xs=[p%rw for p in component];ys=[p//rw for p in component]
        a,c,d,e=min(xs),min(ys),max(xs)+1,max(ys)+1
        if len(component)>80 and .75<(d-a)/(e-c)<1.3:circles.append((len(component),(a,c,d,e)))
    if not circles:raise RuntimeError('No reliable filled dismiss circle')
    _,(a,c,d,e)=max(circles)
    x,y,r,b=w//2+a*scale,c*scale,w//2+d*scale,e*scale
    if name=='dismiss':return (x+r)//2,(y+b)//2
    left=max(0,x-int(1.5*(r-x)));white=im.crop((left,y,x,b))
    wm=Image.new('L',white.size);wm.putdata([255 if min(c)>245 else 0 for c in white.getdata()])
    bounds=wm.getbbox()
    if bounds is None:raise RuntimeError('No white snooze circle')
    a,c,d,e=bounds
    return left+(a+d)//2,y+(c+e)//2

def action(name):
    x,y=action_point(name)
    adb('shell','input','tap',str(x),str(y));time.sleep(.5)

def prepare(name,locked=False,kind=3):
    adb('shell','am','start','-n',PACKAGE+'/com.hwani1103.shiftbell.MainActivity');time.sleep(.5);connect_vm()
    ident=int(evaluate(name+'_create','providers/alarm_provider.dart',"""(() async {
      final d=await DatabaseService.instance.database;final ids=(await d.query('alarms')).map((r)=>r['id']).toSet();
      final at=DateTime.now().add(const Duration(seconds:14));final n=AlarmNotifier();
      try{await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,"0")}:${at.minute.toString().padLeft(2,"0")}',date:at,type:'custom',alarmTypeId:KIND));}finally{n.dispose();}
      return '${(await d.query('alarms')).singleWhere((r)=>!ids.contains(r['id']))['id']}';
    })()""".replace('KIND',str(kind)).replace('\n',' ')))
    adb('shell','input','keyevent','KEYCODE_SLEEP' if locked else 'KEYCODE_HOME')
    for _ in range(35):
        if int(native_state().get('currently_ringing_alarm_id','-1'))==ident:break
        time.sleep(1)
    else:raise RuntimeError('No actual OS delivery')
    time.sleep(.7);capture(name)
    (OUT/(name+'.xml')).write_bytes(ui())
    (OUT/'ring_current.json').write_text(json.dumps({'name':name,'id':ident,'state':native_state(),'locked':locked}),encoding='utf8')
    print('Actual OS delivery',ident,name,flush=True)

def dismiss():
    f=json.loads((OUT/'ring_current.json').read_text(encoding='utf8'));ident=f['id'];name=f['name']
    action('dismiss')
    adb('shell','input','keyevent','KEYCODE_WAKEUP');adb('shell','wm','dismiss-keyguard')
    adb('shell','am','start','-n',PACKAGE+'/com.hwani1103.shiftbell.MainActivity');time.sleep(.7)
    scenario(name+'_dismiss','services/database_service.dart',f'''
      final d=await DatabaseService.instance.database;
      check((await d.query('alarms',where:'id=?',whereArgs:[{ident}])).isEmpty,'native UI removed fired row');
      check(!(await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{ident}}})??true),'ring stopped');
      check((await d.query('alarm_history',where:'alarm_id=?',whereArgs:[{ident}])).length==1,'one final history entry');
    ''')
    assert compare_os(name+'_os')

if __name__=='__main__':
    if sys.argv[1]=='prepare':prepare(sys.argv[2],sys.argv[3]=='locked',int(sys.argv[4]) if len(sys.argv)>4 else 3)
    elif sys.argv[1]=='dismiss':dismiss()
    elif sys.argv[1]=='snooze':action('snooze')
