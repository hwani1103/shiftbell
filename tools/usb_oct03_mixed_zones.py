"""Actual mixed OS reservations across zones; UTC clock is never changed."""
import json
import time
import xml.etree.ElementTree as ET
from usb_audit_device import adb, evaluate, compare_os, OUT
from usb_audit_scenarios import scenario

original_zone=adb('shell','getprop','persist.sys.timezone').decode().strip()
original_auto=adb('shell','settings','get','global','auto_time_zone').decode().strip()
assert original_zone=='Asia/Seoul'
try:
    ident=int(evaluate('mixed_zone_ring_create','providers/alarm_provider.dart',"""(() async {
      final d=await DatabaseService.instance.database;final ids=(await d.query('alarms')).map((r)=>r['id']).toSet();
      final at=DateTime.now().add(const Duration(seconds:8));final n=AlarmNotifier();
      try{await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,"0")}:${at.minute.toString().padLeft(2,"0")}',date:at,type:'custom',alarmTypeId:3));}finally{n.dispose();}
      return '${(await d.query('alarms')).singleWhere((r)=>!ids.contains(r['id']))['id']}';})()""".replace('\n',' ')))
    for _ in range(40):
        values={n.get('name'):n.get('value') for n in ET.fromstring(adb('exec-out','run-as','com.hwani1103.shiftbell.dev','cat','/data/user_de/0/com.hwani1103.shiftbell.dev/shared_prefs/alarm_state.xml'))}
        if int(values.get('currently_ringing_alarm_id','-1'))==ident:break
        time.sleep(1)
    else:raise AssertionError('No actual ring')
    adb('shell','run-as','com.hwani1103.shiftbell.dev','/system/bin/am','broadcast','--user','0',
        '-n','com.hwani1103.shiftbell.dev/com.hwani1103.shiftbell.AlarmActionReceiver',
        '-a','SNOOZE_FROM_NOTIFICATION','--ei','alarmId',str(ident),'--el','ringRound',values['currently_ringing_round'])
    time.sleep(.5)
    scenario('mixed_zone_prepare','providers/alarm_provider.dart',"""
      final d=await DatabaseService.instance.database;final s=(await DatabaseService.instance.getShiftSchedule())!;
      check((await d.query('shift_alarm_templates')).isEmpty,'original templates empty');
      check((await d.query('alarms',where:"type='snoozed'")).length==1,'genuine native snooze exists');
      await DatabaseService.instance.replaceAllAlarmTemplates([
        {'shift_type':s.pattern!.first,'time':'23:41','alarm_type_id':3,'day_offset':0},
        {'shift_type':s.pattern!.last,'time':'23:42','alarm_type_id':3,'day_offset':0}]);
      await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
      final fixed=await d.query('alarms',where:"type='fixed'",orderBy:'date');
      check(fixed.length>=2,'fixed fixtures generated');
      final n=AlarmNotifier();try{await n.updateAlarmType(fixed[0]['id'] as int,2);
        await n.deleteAlarm(fixed[1]['id'] as int,DateTime.parse(fixed[1]['date'] as String));}finally{n.dispose();}
      check((await d.query('alarm_overrides')).length==2,'set_type and skip prepared');
    """)
    original=json.loads(evaluate('export_mixed_zone_reference','services/database_service.dart',f"""(() async {{
      final d=await DatabaseService.instance.database;return jsonEncode({{'snooze':(await d.query('alarms',where:'id=?',whereArgs:[{ident}])).single,
        'overrides':await d.query('alarm_overrides',orderBy:'id')}});}})()""".replace('\n',' ')))
    adb('shell','settings','put','global','auto_time_zone','0')
    for zone in ['America/New_York','Europe/London','Asia/Seoul']:
        adb('shell','cmd','alarm','set-timezone',zone)
        assert adb('shell','getprop','persist.sys.timezone').decode().strip()==zone
        tag=zone.replace('/','_')
        evaluate('mixed_zone_refresh_'+tag,'services/database_service.dart',"(() async {return '${await kAlarmChannel.invokeMethod<bool>('forceNativeRefreshAndWait')}';})()")
        now=json.loads(evaluate('export_mixed_zone_'+tag,'services/database_service.dart',f"""(() async {{
          final d=await DatabaseService.instance.database;return jsonEncode({{'snooze':(await d.query('alarms',where:'id=?',whereArgs:[{ident}])).single,
            'overrides':await d.query('alarm_overrides',orderBy:'id')}});}})()""".replace('\n',' ')))
        assert now==original,'snooze absolute row or user exception changed'
        assert compare_os('mixed_zone_'+tag+'_os')
    (OUT/'mixed_zone_result.json').write_text(json.dumps({'zones':['America/New_York','Europe/London','Asia/Seoul'],
        'snooze_id':ident,'snooze_and_overrides_preserved':True,'all_zone_db_os_match':True,'utc_clock_changed':False}),encoding='utf-8')
finally:
    adb('shell','cmd','alarm','set-timezone',original_zone)
    adb('shell','settings','put','global','auto_time_zone',original_auto)
    import usb_oct03_restore_baseline
print('PASS mixed fixed/custom/real snooze/skip/set_type zone changes; original zone and data restored.')
