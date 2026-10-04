"""Device evidence helper. Explicit dev serial/package; never touches prod data."""
import json
import pathlib
import subprocess
import sys
import time
import re
import os
import xml.etree.ElementTree as ET
from datetime import datetime

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / os.environ.get('SHIFTBELL_AUDIT_OUT', 'build/usb_audit_2026-09-30')
OUT.mkdir(parents=True, exist_ok=True)
ADB = 'C:/Users/Administrator/AppData/Local/Android/sdk/platform-tools/adb.exe'
DART = 'C:/tools/flutter/bin/cache/dart-sdk/bin/dart.exe'
SERIAL = os.environ.get('SHIFTBELL_AUDIT_SERIAL', 'R5KL20DHWAE')
VM_PORT = os.environ.get('SHIFTBELL_AUDIT_VM_PORT', '58181')
PACKAGE = 'com.hwani1103.shiftbell.dev'


def adb(*args, timeout=45):
    return subprocess.run([ADB, '-s', SERIAL, *args], capture_output=True,
                          check=True, timeout=timeout).stdout


def connect_vm():
    pid=adb('shell','pidof',PACKAGE).decode().strip().split()[0]
    log=adb('logcat','-d','--pid='+pid,'-s','flutter').decode('utf-8',errors='replace')
    urls=re.findall(r'The Dart VM service is listening on (http://127.0.0.1:\d+/\S+)',log)
    if not urls and (OUT/'vm.json').exists():
        # Long SRTL runs can rotate the original VM announcement out of logcat.
        previous=json.loads((OUT/'vm.json').read_text(encoding='utf-8'))
        if previous.get('pid',pid)==pid:
            return
    if not urls:
        raise RuntimeError('No VM service announcement for current dev process; attach again')
    url=urls[-1]
    port=url.split(':')[2].split('/')[0]
    adb('forward','tcp:'+VM_PORT,'tcp:'+port)
    config={'uri':re.sub(r'http://127.0.0.1:\d+','ws://127.0.0.1:'+VM_PORT,url).rstrip('/')+'/ws','pid':pid}
    (OUT/'vm.json').write_text(json.dumps(config),encoding='utf-8')


def evaluate(name, library, expression, wait=True, timeout=90):
    config = json.loads((OUT / 'vm.json').read_text(encoding='utf-8'))
    dds_uri = os.environ.get('SHIFTBELL_AUDIT_DDS_URL')
    if dds_uri:
        config['uri'] = dds_uri
    config.update(library=library, expression=expression, **{'await': wait,
                  'timeoutSeconds': timeout})
    path = OUT / (name + '.request.json')
    path.write_text(json.dumps(config, ensure_ascii=False), encoding='utf-8')
    runner = ['node', str(ROOT / 'tools/usb_vm_audit.mjs')] if dds_uri else [DART, str(ROOT / 'tools/usb_vm_audit.dart')]
    result = subprocess.run([*runner, str(path)],
                            capture_output=True, timeout=timeout + 30)
    (OUT / (name + '.vm.json')).write_bytes(result.stdout)
    (OUT / (name + '.stderr.log')).write_bytes(result.stderr)
    if result.returncode:
        raise RuntimeError(result.stderr.decode('utf-8', errors='replace'))
    value = json.loads(result.stdout)
    text = value.get('valueAsString')
    if text is None:
        raise RuntimeError('Non-string VM result: ' + str(value))
    print(name, text[:1200] if name.startswith('export_') is False else f'{len(text)} characters saved')
    return text


def capture(name):
    # Let route transitions settle before recording pixels (XML is slower).
    time.sleep(float(os.environ.get('SRTL_CAPTURE_SETTLE', '.8')))
    pixels = adb('exec-out', 'screencap', '-p')
    # Android 17 multi-display screencap may prepend a warning on stdout.
    start = pixels.find(b'\x89PNG\r\n\x1a\n')
    if start < 0:
        raise RuntimeError('screencap returned no PNG')
    # A dropped SRTL connection can return a PNG header with a truncated body.
    # Do not report that partial transfer as a successful screenshot.
    from io import BytesIO
    from PIL import Image
    with Image.open(BytesIO(pixels[start:])) as screenshot:
        screenshot.verify()
    (OUT / (name + '.png')).write_bytes(pixels[start:])
    if os.environ.get('SHIFTBELL_AUDIT_XML', '1') == '0':
        return
    adb('shell', 'uiautomator', 'dump', '/sdcard/usb_audit_ui.xml')
    (OUT / (name + '.xml')).write_bytes(adb('exec-out', 'cat', '/sdcard/usb_audit_ui.xml'))


def tap_text(pattern):
    adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
    data=adb('exec-out','cat','/sdcard/usb_audit_ui.xml')
    nodes=[n for n in ET.fromstring(data).iter('node')
           if re.search(pattern,n.get('text','') or n.get('content-desc',''))]
    if len(nodes)!=1:
        raise RuntimeError(f'Expected one UI match for {pattern!r}, found {len(nodes)}')
    x1,y1,x2,y2=map(int,re.findall(r'\d+',nodes[0].get('bounds')))
    adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
    time.sleep(.4)


def compare_os(name):
    rows=json.loads(evaluate(name+'_rows','services/database_service.dart',
        "(() async {final d=await DatabaseService.instance.database;return jsonEncode((await d.query('alarms')).map((r)=>{'id':r['id'],'epoch':Alarm.fromMap(r).date!.millisecondsSinceEpoch}).toList());})()"))
    dump=adb('shell','dumpsys','alarm').decode('utf-8',errors='replace')
    (OUT/(name+'_alarmmanager.txt')).write_text(dump,encoding='utf-8')
    pattern=r'RTC_WAKEUP #\d+: Alarm\{[^\n]+origWhen (\d+)[^\n]+ com\.hwani1103\.shiftbell\.dev\}\r?\n\s+tag=[^\n]*CustomAlarmReceiver'
    actual=sorted(map(int,re.findall(pattern,dump)))
    device_now=int(adb('shell','date','+%s').decode().strip())*1000
    expected=sorted(r['epoch']//1000*1000 for r in rows
                    if r['epoch']>device_now)
    result={'expected':expected,'actual':actual,'match':actual==expected}
    (OUT/(name+'.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(name,'DB',len(expected),'OS',len(actual),'match',result['match'])
    return result['match']


if __name__ == '__main__':
    if sys.argv[1] == 'capture':
        capture(sys.argv[2])
    else:
        evaluate(sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3]).read_text(encoding='utf-8'))
