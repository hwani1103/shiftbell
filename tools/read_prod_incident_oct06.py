"""Read-only evidence extraction for prod early-alarm incident."""
import json,re,subprocess,pathlib,datetime
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=ROOT/'build/usb_prod_incident_2026-10-06'
ADB='C:/Users/Administrator/AppData/Local/Android/sdk/platform-tools/adb.exe'
def read(path):
    data=path.read_bytes()
    return data.decode('utf-16' if data.startswith(b'\xff\xfe') else 'utf-8-sig',errors='replace')
def adb(*args):
    return subprocess.run([ADB,'-s','R5KL20DHWAE',*args],capture_output=True,check=True).stdout
def local(ms):
    return datetime.datetime.fromtimestamp(ms/1000,datetime.timezone(datetime.timedelta(hours=9))).isoformat()
if __name__=='__main__':
    if (OUT/'alarmmanager_current.txt').exists():
        current=read(OUT/'alarmmanager_current.txt')
        intents=read(OUT/'pending_intents_current.txt')
        mapping={}
        for part in re.split(r'(?=PendingIntentRecord\{)',intents):
            m=re.match(r'PendingIntentRecord\{([a-f0-9]+) com\.hwani1103\.shiftbell broadcastIntent\}',part)
            ident=re.search(r'dat=shiftbell://alarm/(\d+)',part)
            if m and ident:mapping[m[1]]=int(ident[1])
        future=[]
        for block in re.split(r'(?=\s+(?:RTC_WAKEUP|RTC|ELAPSED_WAKEUP|ELAPSED) #\d+: Alarm\{)',current):
            if not any(' com.hwani1103.shiftbell}' in l for l in block.splitlines()[:4]):continue
            if 'tag=*walarm*:com.hwani1103.shiftbell/.CustomAlarmReceiver' not in block:continue
            epoch=re.search(r'origWhen (\d+)',block)
            operation=re.search(r'operation=PendingIntent\{[^\n]*PendingIntentRecord\{([a-f0-9]+)',block)
            if epoch and operation:future.append({'id':mapping.get(operation[1]),'epoch':int(epoch[1]),'seoul':local(int(epoch[1]))})
        backup=json.loads((OUT/'ShiftBell_Backup_261006_1140.json').read_bytes())
        creation={r['alarm_id']:r for r in backup['tables']['alarm_creation_log']}
        for r in future:
            item=creation.get(r['id'])
            r['recorded_date']=item.get('scheduled_date') if item else None
            r['matches_recorded_seoul_wall']=bool(r['recorded_date']) and datetime.datetime.fromisoformat(r['seoul']).replace(tzinfo=None)==datetime.datetime.fromisoformat(r['recorded_date'])
        (OUT/'current_prod_reservations.json').write_text(json.dumps(future,ensure_ascii=False,indent=2),encoding='utf-8')
        print('CURRENT PROD ALARMS',future)
        print('YESTERDAY HISTORY',[r for r in backup['tables']['alarm_history'] if r.get('scheduled_date','').startswith('2026-10-05')])
        raise SystemExit(0)
    for name in ['ShiftBell_Backup_261006_0753.json','ShiftBell_Backup_261006_1140.json']:
        content=adb('exec-out','cat','/sdcard/Download/ShiftBell/'+name)
        (OUT/name).write_bytes(content)
        data=json.loads(content)
        tables=data.get('tables',{})
        print(name,'top keys',list(data),'tables',list(tables))
        for key in ['alarms','alarm_history','alarm_creation_log','shift_alarm_templates']:
            rows=tables.get(key,[])
            print(key,'count',len(rows))
            if key=='alarms':print(rows)
            if key in ['alarm_history','alarm_creation_log']: print([r for r in rows if r.get('alarm_id')==53 or '2026-10-06' in str(r.get('created_at',''))])
    text=read(OUT/'logcat_epoch.txt')
    selected=[]
    for line in text.splitlines():
        m=re.match(r'\s*(\d+\.\d+)\s+(\d+)\s+\d+\s+[A-Z]\s+([^:]+):\s*(.*)',line)
        if not m:continue
        epoch,pid,tag,msg=m.groups()
        if pid=='32357' and (tag in ['CustomAlarmReceiver','AlarmActionHelper','AlarmActionReceiver','AlarmHistoryHelper','AlarmGuardReceiver','AlarmRefreshEngine','AlarmOverlay'] or 'history' in msg.lower()):
            selected.append(f'{local(float(epoch)*1000)} pid={pid} {tag}: {msg}')
    (OUT/'prod_timeline.txt').write_text('\n'.join(selected),encoding='utf-8')
    print('INCIDENT END:')
    print('\n'.join(selected[-45:]))
    results=[]
    for path in sorted((ROOT/'build/usb_regional_audit_2026-10-06').glob('*alarmmanager.txt')):
        text=read(path)
        blocks=re.split(r'(?=\s+(?:RTC_WAKEUP|RTC|ELAPSED_WAKEUP|ELAPSED) #\d+: Alarm\{)',text)
        found=[]
        for block in blocks:
            head=block.splitlines()[:4]
            if not any(' com.hwani1103.shiftbell}' in l for l in head):continue
            m=re.search(r'origWhen (\d+)',block)
            if not m:continue
            epoch=int(m[1])
            if epoch==1791254400000:
                found.append(block[:4500])
        if found:
            results.append({'source':path.name,'blocks':found})
    (OUT/'early_os_reservations.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Earlier OS reservation snapshots:',[r['source'] for r in results])
    if results:print(results[0]['blocks'][0][:2300])
