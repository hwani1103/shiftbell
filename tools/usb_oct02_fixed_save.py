import json,time,base64
from usb_audit_device import evaluate,adb,tap_text,capture,compare_os,OUT
raw=evaluate('export_fixed_save_before','services/database_service.dart',"(() async {final d=await DatabaseService.instance.database;return jsonEncode(await d.query('shift_alarm_templates',orderBy:'id'));})()")
before=json.loads(raw)
# One unsaved 09:00 fixture is currently open in the Night shift dialog.
adb('shell','input','keyevent','KEYCODE_BACK')
adb('shell','input','keyevent','KEYCODE_BACK')
after=evaluate('export_fixed_back_after','services/database_service.dart',"(() async {final d=await DatabaseService.instance.database;return jsonEncode(await d.query('shift_alarm_templates',orderBy:'id'));})()")
assert json.loads(after)==before
tap_text('^편집$');tap_text('^고정 알람 수정');tap_text('^야간');tap_text('알람 추가');tap_text('^확인$');tap_text('^저장$')
capture('fixed_save_page_pending')
adb('shell','input','tap','540','2094');adb('shell','input','tap','540','2094');adb('shell','input','keyevent','KEYCODE_HOME')
time.sleep(1)
after=evaluate('export_fixed_double_save_after','services/database_service.dart',"(() async {final d=await DatabaseService.instance.database;return jsonEncode(await d.query('shift_alarm_templates',orderBy:'id'));})()")
assert len(json.loads(after))==len(before)+1 and len([r for r in json.loads(after) if r['shift_type']=='야간' and r['time']=='09:00'])==1
assert compare_os('fixed_double_save_background_os')
encoded=base64.b64encode(raw.encode()).decode()
evaluate('fixed_double_save_cleanup','services/database_service.dart',f"(() async {{await DatabaseService.instance.replaceAllAlarmTemplates((jsonDecode(utf8.decode(base64Decode('{encoded}'))) as List).map((r)=>Map<String,dynamic>.from(r as Map)).toList());await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');return 'test Night template removed';}})()")
adb('shell','monkey','-p','com.hwani1103.shiftbell.dev','-c','android.intent.category.LAUNCHER','1')
print('PASS fixed editor unsaved back; page save double tap and immediate background; no duplicate template; restored fixtures')
