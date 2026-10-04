"""Actual OS overlap on lock screen and timeout after leaving alarm activity."""
import json,time
from usb_audit_device import adb,OUT,PACKAGE,evaluate,connect_vm,capture,compare_os
from usb_audit_scenarios import scenario
from srtl_current_audit import fold,locale
from srtl_ring_checks import native_state,action,prepare

locale('ko-KR')
scenario('overlap_remove_previous_test_snoozes','providers/alarm_provider.dart',"""
 final d=await DatabaseService.instance.database;final n=AlarmNotifier();
 try{for(final r in await d.query('alarms',where:"type='snoozed'")){await n.deleteAlarm(r['id'] as int,DateTime.parse(r['date'] as String));}}
 finally{n.dispose();}
""")
for opened in [False,True]:
    fold(opened);connect_vm()
    name='srtl_overlap_'+('open' if opened else 'closed')
    ids=json.loads(evaluate(name+'_create','providers/alarm_provider.dart',"""(() async {
      final d=await DatabaseService.instance.database;final n=AlarmNotifier();final result=<int>[];
      try{for(final seconds in [12,72]){
        final before=(await d.query('alarms')).map((r)=>r['id']).toSet();final at=DateTime.now().add(Duration(seconds:seconds));
        await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,"0")}:${at.minute.toString().padLeft(2,"0")}',date:at,type:'custom',alarmTypeId:3));
        result.add((await d.query('alarms')).singleWhere((r)=>!before.contains(r['id']))['id'] as int);
      }}finally{n.dispose();}return result.toString();
    })()""".replace('\n',' ')))
    adb('shell','input','keyevent','KEYCODE_SLEEP')
    rounds=[]
    for number,ident in enumerate(ids):
        deadline=time.monotonic()+85
        while time.monotonic()<deadline:
            state=native_state()
            if int(state.get('currently_ringing_alarm_id','-1'))==ident:break
            time.sleep(1)
        else:raise AssertionError(('Missing actual overlap ring',ident))
        rounds.append(int(state['currently_ringing_round']))
        capture(name+'_ring_'+str(number));print(name,'OS delivered',ident,flush=True)
    adb('shell','run-as',PACKAGE,'/system/bin/am','broadcast','--user','0','-n',PACKAGE+'/com.hwani1103.shiftbell.AlarmActionReceiver',
        '-a','DISMISS_FROM_NOTIFICATION','--ei','alarmId',str(ids[0]),'--el','ringRound',str(rounds[0]))
    assert int(native_state().get('currently_ringing_alarm_id','-1'))==ids[1],'Old UI must not end new ring'
    action('dismiss')
    adb('shell','input','keyevent','KEYCODE_WAKEUP');adb('shell','wm','dismiss-keyguard')
    adb('shell','am','start','-n',PACKAGE+'/com.hwani1103.shiftbell.MainActivity');time.sleep(1);connect_vm()
    scenario(name+'_verify','services/database_service.dart',f"""
      final d=await DatabaseService.instance.database;
      final first=await d.query('alarm_history',where:'alarm_id=?',whereArgs:[{ids[0]}]);
      check(first.length==1 && first.single['dismiss_type']=='superseded_by_next_alarm','old ring finalized exactly once');
      check((await d.query('alarm_history',where:'alarm_id=?',whereArgs:[{ids[1]}])).length==1,'new ring finalized once');
      for(final id in {ids})check((await d.query('alarms',where:'id=?',whereArgs:[id])).isEmpty,'no ghost row');
    """)
    assert compare_os(name+'_os')
    (OUT/(name+'.json')).write_text(json.dumps({'ids':ids,'rounds':rounds,'actual_os_delivery':True,'stale_old_action_ignored':True}),encoding='utf8')

fold(False)
duration=evaluate('timeout_original_duration','services/database_service.dart',"(() async {final d=await DatabaseService.instance.database;final row=(await d.query('alarm_types',where:'id=3')).single;await d.update('alarm_types',{'duration':1},where:'id=3');return row['duration'].toString();})()")
try:
    prepare('srtl_native_timeout_start',True,3)
    current=json.loads((OUT/'ring_current.json').read_text(encoding='utf8'));ident=current['id'];start=time.monotonic()
    adb('shell','input','keyevent','KEYCODE_HOME')
    while time.monotonic()-start<85:
        if int(native_state().get('currently_ringing_alarm_id','-1'))!=ident:break
        time.sleep(1)
    else:raise AssertionError('Timeout failed after leaving native alarm activity')
    capture('srtl_native_timeout_finished')
    adb('shell','input','keyevent','KEYCODE_WAKEUP');adb('shell','wm','dismiss-keyguard')
    adb('shell','am','start','-n',PACKAGE+'/com.hwani1103.shiftbell.MainActivity');time.sleep(1);connect_vm()
    scenario('srtl_native_timeout_verify','services/database_service.dart',f"""
      final d=await DatabaseService.instance.database;final h=await d.query('alarm_history',where:'alarm_id=?',whereArgs:[{ident}]);
      check(h.length==1 && h.single['dismiss_type']=='timeout','native timeout ended one round');
      check((await d.query('alarms',where:'id=?',whereArgs:[{ident}])).isEmpty,'timed out custom row removed');
    """)
    assert compare_os('srtl_native_timeout_os')
finally:
    evaluate('timeout_restore_duration','services/database_service.dart',f"(() async {{final d=await DatabaseService.instance.database;await d.update('alarm_types',{{'duration':{int(duration)}}},where:'id=3');return 'restored';}})()")
print('PASS locked overlap in both postures and actual timeout after HOME.',flush=True)
