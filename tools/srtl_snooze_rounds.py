"""Real five-minute snooze, fold during ringing and notification action races."""
import json,time
from concurrent.futures import ThreadPoolExecutor
from usb_audit_device import adb,OUT,PACKAGE,connect_vm,capture,compare_os
from usb_audit_scenarios import scenario
from srtl_ring_checks import prepare,action,native_state
from srtl_current_audit import fold

fold(False)
prepare('srtl_real_snooze_first',True,3)
first=json.loads((OUT/'ring_current.json').read_text(encoding='utf8'))
ident=first['id'];old=int(first['state']['currently_ringing_round'])
action('snooze');start=time.monotonic()
print('Real five-minute wait started; clock unchanged.',flush=True)
while time.monotonic()-start<340:
    state=native_state()
    if int(state.get('currently_ringing_alarm_id','-1'))==ident and int(state.get('currently_ringing_round','-1'))!=old:
        break
    elapsed=int(time.monotonic()-start)
    if elapsed%30==0:print('Snooze elapsed',elapsed,flush=True)
    time.sleep(1)
else:raise RuntimeError('No second OS-delivered ring')
elapsed=time.monotonic()-start
assert elapsed>=285, ('Re-ring was early',elapsed)
new=int(state['currently_ringing_round'])
capture('srtl_real_snooze_second_closed')
fold(True);capture('srtl_real_snooze_second_open')
assert int(native_state().get('currently_ringing_alarm_id','-1'))==ident

def send(name,round_):
    result=adb('shell','run-as',PACKAGE,'/system/bin/am','broadcast','--user','0',
        '-n',PACKAGE+'/com.hwani1103.shiftbell.AlarmActionReceiver','-a',name,
        '--ei','alarmId',str(ident),'--el','ringRound',str(round_))
    assert b'Broadcast completed' in result

for name in ['DISMISS_FROM_NOTIFICATION','SNOOZE_FROM_NOTIFICATION']:send(name,old)
state=native_state()
assert int(state.get('currently_ringing_alarm_id','-1'))==ident
assert int(state.get('currently_ringing_round','-1'))==new
with ThreadPoolExecutor(max_workers=2) as pool:
    futures=[pool.submit(send,name,new) for name in ['DISMISS_FROM_NOTIFICATION','SNOOZE_FROM_NOTIFICATION']]
    for future in futures:future.result()
time.sleep(1)
adb('shell','input','keyevent','KEYCODE_WAKEUP');adb('shell','wm','dismiss-keyguard')
adb('shell','am','start','-n',PACKAGE+'/com.hwani1103.shiftbell.MainActivity');time.sleep(1);connect_vm()
scenario('srtl_real_snooze_round_contract','services/database_service.dart',f'''
 final d=await DatabaseService.instance.database;
 check(!(await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{{'alarmId':{ident}}})??true),'new round ended');
 check((await d.query('alarm_history',where:'alarm_id=?',whereArgs:[{ident}])).length==2,'exactly one result per round, none from stale actions');
 final rows=await d.query('alarms',where:'id=?',whereArgs:[{ident}]);
 check(rows.isEmpty || (rows.length==1 && rows.single['type']=='snoozed'),'one winning final result');
''')
assert compare_os('srtl_real_snooze_round_os')
(OUT/'srtl_real_snooze_rounds.json').write_text(json.dumps({'id':ident,'first':old,'second':new,
    'elapsed_seconds':elapsed,'clock_changed':False,'fold_during_ring':True,'stale_round_ignored':True,
    'race':'same-app UID notification receiver broadcasts'}),encoding='utf8')
print('PASS real snooze, fold while ringing, stale actions and current-round first-wins.',flush=True)
