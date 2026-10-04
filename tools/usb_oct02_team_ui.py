import json, base64, time
from usb_audit_device import adb, capture, tap_text, evaluate, compare_os, OUT

def state(name):
    return json.loads(evaluate(name,'screens/settings_tab.dart',"""(() async {
      final p=await SharedPreferences.getInstance();final d=await DatabaseService.instance.database;
      return jsonEncode({'myTeam':p.getString('all_teams_my_team'),'names':p.getStringList('all_teams_names'),
      'offsets':p.getString('all_teams_offsets'),'schedule':(await DatabaseService.instance.getShiftSchedule())!.toMap(),
      'alarms':await d.query('alarms',orderBy:'id')});})()""".replace('\n',' ')))

def open_change():
    tap_text('^편집$');tap_text('^스케줄 변경')

before=state('team_ui_before')
assert before['myTeam']=='A' and before['names']==['A','B','D']
try:
    # Popup already opened by real taps. Fourth slot is D on this fixture/day.
    adb('shell','input','tap','546','1190');tap_text('^저장$')
    capture('team_ui_A_to_D_toast')
    after=state('team_ui_after_D')
    assert after['myTeam']=='D' and after['offsets']==before['offsets'] and after['names']==before['names']
    assert after['alarms']==before['alarms']
    assert compare_os('team_ui_D_os')
    open_change();adb('shell','input','tap','186','1190');tap_text('^저장$')
    capture('team_ui_unmatched_warning')
    tap_text('^취소$')
    cancelled=state('team_ui_unmatched_cancel')
    assert cancelled==after
    tap_text('^저장$');tap_text('^확인$');capture('team_ui_unmatched_confirm_toast')
    cleared=state('team_ui_after_clear')
    assert cleared['myTeam'] is None and cleared['names'] is None and cleared['offsets'] is None
    assert cleared['alarms']==before['alarms']
    assert compare_os('team_ui_clear_os')
    print('PASS: actual taps A->D, roster preserved, unmatched cancel/confirm, original alarm unchanged')
finally:
    encoded=base64.b64encode(json.dumps(before,ensure_ascii=False).encode()).decode()
    evaluate('team_ui_restore_original','screens/settings_tab.dart',f"""(() async {{
      final data=jsonDecode(utf8.decode(base64Decode('{encoded}'))) as Map;
      final p=await SharedPreferences.getInstance();
      await p.setStringList('all_teams_names',(data['names'] as List).cast<String>());
      await p.setString('all_teams_offsets',data['offsets'] as String);
      await p.setString('all_teams_my_team',data['myTeam'] as String);
      final s=ShiftSchedule.fromMap(Map<String,dynamic>.from(data['schedule'] as Map));
      await DatabaseService.instance.updateShiftSchedule(s);
      await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
      return 'original schedule and team preferences restored'; }})()""".replace('\n',' '))
