"""Follow-up device audit. No sleep/power/lock/reboot commands; dev package only."""
import os
os.environ['SHIFTBELL_AUDIT_OUT'] = 'build/usb_regional_audit_2026-10-06'
import json, sys, time, hashlib, re, xml.etree.ElementTree as ET
from pathlib import Path
from usb_audit_device import adb, OUT, PACKAGE, connect_vm, evaluate, capture, tap_text, compare_os

def save(name, data):
    (OUT / name).write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')

def power():
    state = adb('shell', 'dumpsys', 'power').decode(errors='replace')
    assert 'mWakefulness=Awake' in state and 'mStayOn=true' in state
    assert 'mIsPowered=true' in state
    return {'awake': True, 'stay_on': True, 'powered': True}

def launch():
    adb('shell','am','start','-W','-n',PACKAGE+'/com.hwani1103.shiftbell.MainActivity')
    time.sleep(2)
    connect_vm()

def permissions(name):
    return json.loads(evaluate(name,'services/database_service.dart',
        "(() async => jsonEncode(await kAlarmChannel.invokeMethod('permissionSnapshot')))()"))

def all_tables(name):
    return json.loads(evaluate('export_'+name,'services/database_service.dart',"""(() async {
      final d=await DatabaseService.instance.database;
      final tables=await d.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
      final result=<String,dynamic>{};
      for(final t in tables){final n=t['name'] as String;result[n]=await d.query(n,orderBy:'rowid');}
      return jsonEncode(result);
    })()""".replace('\n',' ')))

def ui(name):
    capture(name)
    nodes=list(ET.parse(OUT/(name+'.xml')).iter('node'))
    print([(n.get('text') or n.get('content-desc'),n.get('bounds'),n.get('checked')) for n in nodes if n.get('text') or n.get('content-desc') or n.get('checkable')=='true'])
    return nodes

def native_open(kind):
    evaluate(kind+'_settings_open','services/database_service.dart',
       "(() async => jsonEncode(await kAlarmChannel.invokeMethod('openPermissionSettings',{'kind':"+repr(kind)+"})))()")

def tap_node(n):
    a,b,c,d=map(int,re.findall(r'\d+',n.get('bounds')))
    adb('shell','input','tap',str((a+c)//2),str((b+d)//2))
    time.sleep(.5)

if __name__ == '__main__':
    stage=sys.argv[1]
    if stage=='baseline':
        baseline={'power':power()}
        for key,args in {
            'zone':['getprop','persist.sys.timezone'],
            'auto_zone':['settings','get','global','auto_time_zone'],
            'stay':['settings','get','global','stay_on_while_plugged_in'],
            'locales':['cmd','locale','get-app-locales',PACKAGE],
            'appops':['cmd','appops','get',PACKAGE],
            'package':['dumpsys','package',PACKAGE],
        }.items(): baseline[key]=adb('shell',*args).decode(errors='replace').strip()
        save('baseline_device.json',baseline)
        for location in ['user','user_de']:
            (OUT/('baseline_'+location+'.tar')).write_bytes(adb('exec-out','run-as',PACKAGE,'tar','-C',f'/data/{location}/0/{PACKAGE}','-cf','-','.'))
        manifest=json.loads(Path('docs/next_version/지역시간_수정_2026-10-06/검증_명세.json').read_text(encoding='utf-8'))
        changed=[p for p,h in manifest['source_hashes'].items() if not Path(p).exists() or hashlib.sha256(Path(p).read_bytes()).hexdigest()!=h]
        save('source_baseline_comparison.json',{'checked':len(manifest['source_hashes']),'changed':changed})
        print('Baseline saved; source differences:',changed)
    elif stage=='start':
        launch()
        all_tables('initial_tables')
        save('initial_permissions.json',permissions('initial_permissions'))
        capture('initial_app')
        print(power())
    elif stage=='capture':
        capture(sys.argv[2])
        print(power())
    elif stage=='permissions':
        launch()
        print(permissions(sys.argv[2]))
    elif stage=='ui':
        ui(sys.argv[2])
    elif stage=='tap':
        tap_text(sys.argv[2]);ui(sys.argv[3])
    elif stage=='open':
        native_open(sys.argv[2]);ui(sys.argv[2]+'_settings')
    elif stage=='toggle':
        nodes=ui(sys.argv[2]+'_before_toggle')
        switches=[n for n in nodes if n.get('checkable')=='true']
        assert len(switches)==1,len(switches)
        tap_node(switches[0]);ui(sys.argv[2]+'_after_toggle')
    elif stage=='back':
        adb('shell','input','keyevent','4');time.sleep(.7);ui(sys.argv[2])
    elif stage=='fsi_finish':
        assert permissions('fsi_denied')['fullScreen']=='denied'
        tap_text('^알람 권한 설정$')
        tap_text('^설정$');ui('fsi_actual_button_settings')
        adb('shell','input','keyevent','4');ui('fsi_no_change_return')
        assert permissions('fsi_no_change')['fullScreen']=='denied'
        tap_text('^설정$')
        nodes=ui('fsi_before_restore');switches=[n for n in nodes if n.get('checkable')=='true']
        assert len(switches)==1 and switches[0].get('checked')=='false'
        tap_node(switches[0]);adb('shell','input','keyevent','4');ui('fsi_restored_return')
        assert permissions('fsi_restored')['fullScreen']=='granted'
        save('fsi_result.json',{'off_return':'PASS','app_button_route':'PASS','unchanged_return_denied':'PASS','on_return':'PASS','locked_alarm':'NOT_RUN'})
    elif stage=='overlay_cycle':
        tap_text(r'^교대시계 \(테스트\),');ui('overlay_off_settings')
        adb('shell','input','keyevent','4');ui('overlay_off_return')
        assert permissions('overlay_denied')['overlay']=='denied'
        tap_text('^설정$');ui('overlay_app_button_list')
        adb('shell','input','keyevent','4');ui('overlay_unchanged_return')
        assert permissions('overlay_unchanged')['overlay']=='denied'
        tap_text('^설정$');tap_text(r'^교대시계 \(테스트\),')
        adb('shell','input','keyevent','4');ui('overlay_restored_return')
        assert permissions('overlay_restored')['overlay']=='granted'
        save('overlay_result.json',{'off_return':'PASS','app_button_list':'PASS','unchanged_return_denied':'PASS','on_return':'PASS'})
    elif stage=='notification_toggle':
        nodes=ui(sys.argv[2]+'_before')
        targets=[n for n in nodes if n.get('checkable')=='true' and (n.get('text')=='알림 허용' or n.get('content-desc')=='알림 허용')]
        assert len(targets)==1,len(targets)
        tap_node(targets[0]);ui(sys.argv[2]+'_after')
    elif stage=='channel_finish':
        tap_text('^설정$');ui('channel_app_button')
        adb('shell','input','keyevent','4');ui('channel_unchanged_return')
        value=permissions('channel_unchanged')
        assert value['notification']=='granted' and value['alarmChannel']=='denied'
        tap_text('^설정$')
        nodes=ui('channel_restore_before')
        target=next(n for n in nodes if n.get('checkable')=='true' and (n.get('text')=='알림 허용' or n.get('content-desc')=='알림 허용'))
        assert target.get('checked')=='false';tap_node(target)
        adb('shell','input','keyevent','4');ui('channel_restored_return')
        assert permissions('channel_restored')['alarmChannel']=='granted'
        save('channel_result.json',{'app_notification_separate':'PASS','off_return':'PASS','app_button_route':'PASS','unchanged_return_denied':'PASS','on_return':'PASS'})
    elif stage=='zones':
        original=json.loads((OUT/'baseline_device.json').read_text(encoding='utf-8'))
        matrix=[('America/New_York',-300,-240),('America/Los_Angeles',-480,-420),('America/Phoenix',-420,-420),('Pacific/Honolulu',-600,-600),('Europe/London',0,60),('Europe/Berlin',60,120),('Africa/Johannesburg',120,120),('Asia/Manila',480,480),('Asia/Dubai',240,240),('America/Sao_Paulo',-180,-180),('America/Rio_Branco',-300,-300),('Asia/Kolkata',330,330),('Australia/Lord_Howe',660,630),('Asia/Seoul',540,540)]
        results=[]
        try:
            adb('shell','settings','put','global','auto_time_zone','0')
            for zone,jan,jul in matrix:
                adb('shell','cmd','alarm','set-timezone',zone)
                time.sleep(1)
                assert adb('shell','getprop','persist.sys.timezone').decode().strip()==zone
                result=evaluate('calendar_'+zone.replace('/','_'),'services/work_hours_calculator.dart',Path('tools/usb_oct06_calendar_expression.dart.txt').read_text().replace('\n',' '))
                assert result.startswith('PASS') and f'janOffset={jan} julOffset={jul}' in result,result
                results.append({'zone':zone,'result':result,'power':power()})
                save('regional_device_calendar_results.json',results)
        finally:
            adb('shell','cmd','alarm','set-timezone',original['zone'])
            adb('shell','settings','put','global','auto_time_zone',original['auto_zone'])
        print('PASS actual OS zones',len(results),'month cases',len(results)*48)
    elif stage=='ring':
        name=sys.argv[2]
        ident=int(evaluate(name+'_create','providers/alarm_provider.dart',"""(() async {
          final d=await DatabaseService.instance.database;final ids=(await d.query('alarms')).map((r)=>r['id']).toSet();
          final at=DateTime.now().add(const Duration(seconds:8));final n=AlarmNotifier();
          try {await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,"0")}:${at.minute.toString().padLeft(2,"0")}',date:at,type:'custom',alarmTypeId:3));}
          finally{n.dispose();}
          return '${(await d.query('alarms')).singleWhere((r)=>!ids.contains(r['id']))['id']}';
        })()""".replace('\n',' ')))
        save(name+'_fixture.json',{'id':ident})
        adb('shell','input','keyevent','3')
        for _ in range(30):
            content=adb('exec-out','run-as',PACKAGE,'cat',f'/data/user_de/0/{PACKAGE}/shared_prefs/alarm_state.xml')
            values={n.get('name'):n.get('value') for n in ET.fromstring(content)}
            if values.get('currently_ringing_alarm_id')==str(ident):break
            time.sleep(1)
        else: raise AssertionError('Alarm did not ring')
        save(name+'_ring_state.json',values);ui(name+'_visible');print(power())
    elif stage=='eval':
        result=evaluate(sys.argv[2],sys.argv[3],Path(sys.argv[4]).read_text(encoding='utf-8').replace('\n',' '))
        print(result)
    elif stage=='ring_action':
        name,action=sys.argv[2:4]
        ident=json.loads((OUT/(name+'_fixture.json')).read_text())['id']
        before=int(adb('shell','date','+%s').decode())*1000
        adb('shell','input','tap','932' if action=='dismiss' else '720','382')
        time.sleep(1)
        result=json.loads(evaluate(name+'_'+action+'_result','services/database_service.dart',"""(() async {
          final d=await DatabaseService.instance.database;
          return jsonEncode({'rows':await d.query('alarms',where:'id=?',whereArgs:[IDENT]),
            'history':await d.query('alarm_history',where:'alarm_id=?',whereArgs:[IDENT]),
            'ringing':await kAlarmChannel.invokeMethod<bool>('isAlarmRinging',{'alarmId':IDENT})});
        })()""".replace('IDENT',str(ident)).replace('\n',' ')))
        assert result['ringing']==False,result
        if action=='dismiss':assert result['rows']==[] and len(result['history'])==(2 if name=='ring_snooze' else 1),result
        else:
            assert len(result['rows'])==1 and result['rows'][0]['type']=='snoozed',result
            from datetime import datetime
            epoch=int(datetime.fromisoformat(result['rows'][0]['date']).timestamp()*1000)
            assert 299000<=epoch-before<=305000,(epoch,before)
            result['target_epoch_ms']=epoch
            assert compare_os(name+'_snoozed_os')
        result['clicked_epoch_ms']=before
        save(name+'_action_result.json',result)
        print(power())
    elif stage=='reservation_zones':
        baseline=json.loads(json.loads((OUT/'export_initial_tables.vm.json').read_text())['valueAsString'])
        assert baseline['shift_alarm_templates']==[]
        ident=json.loads((OUT/'ring_snooze_fixture.json').read_text())['id']
        evaluate('fixed_fixture_prepare','services/database_service.dart',"""(() async {
          final d=await DatabaseService.instance.database;
          if((await d.query('shift_alarm_templates')).isNotEmpty)throw StateError('templates not empty');
          final s=(await DatabaseService.instance.getShiftSchedule())!;
          await DatabaseService.instance.replaceAllAlarmTemplates([{'shift_type':s.pattern!.first,'time':'23:41','alarm_type_id':3,'day_offset':0}]);
          await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
          return jsonEncode(await d.query('alarms'));
        })()""".replace('\n',' '))
        original=json.loads((OUT/'baseline_device.json').read_text(encoding='utf-8'))
        results=[]
        try:
            adb('shell','settings','put','global','auto_time_zone','0')
            for zone in ['America/New_York','Europe/London','Asia/Seoul']:
                adb('shell','cmd','alarm','set-timezone',zone);time.sleep(3)
                tag=zone.replace('/','_')
                rows=all_tables('reservation_'+tag)
                assert rows['alarm_overrides']==baseline['alarm_overrides']
                snooze=next(r for r in rows['alarms'] if r['id']==ident)
                expected=json.loads((OUT/'ring_snooze_action_result.json').read_text())['rows'][0]
                assert snooze==expected
                match=compare_os('reservation_'+tag+'_broadcast_os')
                assert match,'OS reservation mismatch after real timezone broadcast'
                results.append({'zone':zone,'snooze_preserved':True,'overrides_preserved':True,'fixed_count':sum(r['type']=='fixed' for r in rows['alarms']),'db_os_match':match,'power':power()})
                save('reservation_zones_result.json',results)
        finally:
            adb('shell','cmd','alarm','set-timezone',original['zone'])
            adb('shell','settings','put','global','auto_time_zone',original['auto_zone'])
            evaluate('fixed_fixture_cleanup','services/database_service.dart',"""(() async {
              final d=await DatabaseService.instance.database;final rows=await d.query('alarms',where:"type='fixed'");
              for(final row in rows){await kAlarmChannel.invokeMethod('cancelNativeAlarm',{'id':row['id']});}
              await DatabaseService.instance.replaceAllAlarmTemplates([]);
              await d.delete('alarms',where:"type='fixed'");
              await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
              return 'fixed fixtures removed';
            })()""".replace('\n',' '))
    elif stage=='fixed_cleanup':
        evaluate('fixed_fixture_cleanup_retry','services/database_service.dart',"""(() async {
          final d=await DatabaseService.instance.database;final rows=await d.query('alarms',where:"type='fixed'");
          await DatabaseService.instance.replaceAllAlarmTemplates([]);
          await d.delete('alarms',where:"type='fixed'");
          for(final row in rows){await kAlarmChannel.invokeMethod('cancelNativeAlarm',{'id':row['id']});}
          for(final id in [161,162]){await kAlarmChannel.invokeMethod('cancelNativeAlarm',{'id':id});}
          await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
          return jsonEncode({'fixedRemaining':(await d.query('alarms',where:"type='fixed'")).length});
        })()""".replace('\n',' '))
        assert compare_os('after_fixed_cleanup_os')
    elif stage=='snooze_wait':
        fixture=json.loads((OUT/'ring_snooze_fixture.json').read_text())
        target=json.loads((OUT/'ring_snooze_action_result.json').read_text())['target_epoch_ms']
        deadline=time.time()+max(5,target/1000-int(adb('shell','date','+%s').decode())+30)
        adb('shell','input','keyevent','3')
        while time.time()<deadline:
            values={n.get('name'):n.get('value') for n in ET.fromstring(adb('exec-out','run-as',PACKAGE,'cat',f'/data/user_de/0/{PACKAGE}/shared_prefs/alarm_state.xml'))}
            if values.get('currently_ringing_alarm_id')==str(fixture['id']):
                now=int(adb('shell','date','+%s').decode())*1000
                assert target<=now<=target+10000,(target,now)
                save('snooze_actual_refire.json',{'target':target,'observed':now,'delay_ms':now-target,'native_state':values,'power':power()})
                capture('snooze_actual_refire');print('PASS actual 5-minute refire',now-target,'ms after target');break
            time.sleep(1)
        else:raise AssertionError('No actual snooze refire')
