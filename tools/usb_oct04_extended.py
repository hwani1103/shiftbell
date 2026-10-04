"""Reversible, awake-only USB residual checks. Never targets the production app."""
import os,sys,json,time,base64
from pathlib import Path
assert os.environ.get('SHIFTBELL_AUDIT_SERIAL')=='R5KL20DHWAE'
from usb_audit_device import adb,OUT,connect_vm,evaluate,capture,compare_os
from srtl_current_audit import ev,tab,back,invoke

def run(name,lib,body):
    body=body.replace('\n',' ')
    return ev(name,lib,body)
def tap(value,key=False,long=False,tooltip=False):
    condition='e.widget.key==ValueKey(VALUE)' if key else '(e.widget is Text && (e.widget as Text).data==VALUE)'
    if tooltip:condition='(e.widget is IconButton && (e.widget as IconButton).tooltip==VALUE)'
    code="""(() {Element root=WidgetsBinding.instance.rootElement!;Element? dialog;void find(Element e){if(e.widget is Offstage&&(e.widget as Offstage).offstage)return;if(e.widget is Dialog)dialog=e;e.visitChildren(find);}root.visitChildren(find);final found=<String>[];void visit(Element e){if(e.widget is Offstage&&(e.widget as Offstage).offstage)return;if(CONDITION){final b=e.findRenderObject();if(b is RenderBox&&b.hasSize){final p=b.localToGlobal(b.size.center(Offset.zero));final v=View.of(e);final d=v.devicePixelRatio;if(p.dx>=0&&p.dy>=0&&p.dx*d<v.physicalSize.width&&p.dy*d<v.physicalSize.height)found.add('${(p.dx*d).round()},${(p.dy*d).round()}');}}e.visitChildren(visit);}visit(dialog??root);if(found.length!=1)throw StateError('matches=${found.length}');return found.single;})()""".replace('CONDITION',condition).replace('VALUE',json.dumps(value,ensure_ascii=False))
    # ModalRoute.of would register inherited-widget dependencies from an audit
    # expression and corrupt the inspected tree. Read ancestors without subscribing.
    code=code.replace('final found=<String>[];', "bool current(Element e){var active=true;e.visitAncestorElements((a){if(a.widget.runtimeType.toString()=='_ModalScopeStatus'){active=(a.widget as dynamic).isCurrent as bool;return false;}return true;});return active;}final found=<String>[];")
    code=code.replace('if('+condition.replace('VALUE',json.dumps(value,ensure_ascii=False))+')', 'if(current(e)&&('+condition.replace('VALUE',json.dumps(value,ensure_ascii=False))+'))')
    code=code.replace("if(found.length!=1)throw StateError('matches=${found.length}');", "if(found.length!=1)return 'ERROR matches=${found.length}';")
    pos=run('extended_tap','main.dart',code)
    assert not pos.startswith('ERROR'),pos
    if long:adb('shell','input','swipe',*pos.split(','),*pos.split(','),'750')
    else:adb('shell','input','tap',*pos.split(','))
    time.sleep(.45)
def labels(name='extended_labels'):
    return run(name,'main.dart',"""(() {final a=<String>[];void visit(Element e){if(e.widget is Offstage&&(e.widget as Offstage).offstage)return;if(e.widget is Text){final w=e.widget as Text;a.add(w.data??w.textSpan?.toPlainText()??'');}e.visitChildren(visit);}WidgetsBinding.instance.rootElement!.visitChildren(visit);return a.join('|');})()""")
def clock(h,m):
    run('extended_prepare_clock','widgets/alarm_time_editor.dart',f"""(() {{AlarmTimePickerState? s;void visit(Element e){{if(e is StatefulElement&&e.state is AlarmTimePickerState)s=e.state as AlarmTimePickerState;e.visitChildren(visit);}}WidgetsBinding.instance.rootElement!.visitChildren(visit);s!.setState((){{s!._hour={h};s!._minute={m};}});return 'unsaved picker time prepared';}})()""")
def panel():
    opened=run('extended_panel_state','screens/calendar_tab.dart',"""(() {String result='missing';void visit(Element e){if(e is StatefulElement&&e.state is _CalendarTabState)result=(e.state as _CalendarTabState)._alarmPanelOpen.toString();e.visitChildren(visit);}WidgetsBinding.instance.rootElement!.visitChildren(visit);return result;})()""")
    assert opened in ['true','false']
    if opened=='false':tap('one-tap-open',True)
def clear_fixed():
    run('extended_clear_fixed','services/database_service.dart',"""(() async {await DatabaseService.instance.replaceAllAlarmTemplates([]);await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');return 'temporary fixed templates cleared';})()""")
def snapshot(name):
    raw=run('export_'+name,'services/database_service.dart',"""(() async {final d=await DatabaseService.instance.database;return jsonEncode({for(final n in ['alarms','shift_alarm_templates','alarm_history','alarm_creation_log','alarm_overrides','shift_schedule','condition_shift_times'])n:await d.query(n,orderBy:'rowid')});})()""")
    (OUT/(name+'.json')).write_text(raw,encoding='utf8');assert compare_os(name+'_os');return json.loads(raw)
def fixed():
    tab(4);tap('편집');tap('고정 알람 수정')
def fixed_add(h,m):
    tap('주간');tap('알람 추가');clock(h,m);tap('확인');tap('저장');tap('저장');time.sleep(.9)
def prep():
    run('extended_tomorrow_fixture','services/database_service.dart',"""(() async {final db=DatabaseService.instance;final d=await db.database;if((await d.query('alarms')).isNotEmpty||(await d.query('shift_alarm_templates')).isNotEmpty)throw StateError('baseline not empty');final old=(await db.getShiftSchedule())!;final days={...?old.assignedDates,'2026-10-05':'주간'};final s=ShiftSchedule.fromMap({...old.toMap(),'assigned_dates':jsonEncode(days)});await db.updateShiftSchedule(s);return 'only tomorrow assignment prepared';})()""")
    sync_schedule()
def sync_schedule():
    run('extended_sync_schedule','screens/settings_tab.dart',"""(() async {final schedule=(await DatabaseService.instance.getShiftSchedule())!;ConsumerState? state;void visit(Element e){if(e is StatefulElement&&e.state is ConsumerState)state??=e.state as ConsumerState;e.visitChildren(visit);}WidgetsBinding.instance.rootElement!.visitChildren(visit);if(state==null)throw StateError('no consumer state');state!.ref.read(scheduleProvider.notifier).applyExternallyPersisted(schedule);await state!.ref.read(conditionShiftTimeProvider.notifier).refresh();return 'schedule and clock providers synchronized';})()""")
def clean():
    snapshot('extended_before_cleanup')
    old=json.loads((OUT/'oct04_original_tables.json').read_text(encoding='utf8'))
    assert not any(old[k] for k in ['alarms','shift_alarm_templates','alarm_history','alarm_creation_log','alarm_overrides','condition_shift_times'])
    encoded=base64.b64encode(json.dumps(old['shift_schedule'][0],ensure_ascii=False).encode()).decode()
    run('extended_cleanup_alarms','providers/alarm_provider.dart',"""(() async {final d=await DatabaseService.instance.database;await DatabaseService.instance.replaceAllAlarmTemplates([]);final n=AlarmNotifier();try{for(final row in await d.query('alarms')){await n.deleteAlarm(row['id'] as int,DateTime.parse(row['date'] as String));}}finally{n.dispose();}return 'temporary alarms removed';})()""")
    run('extended_restore_schedule','services/database_service.dart',f"""(() async {{final s=ShiftSchedule.fromMap(Map<String,dynamic>.from(jsonDecode(utf8.decode(base64Decode('{encoded}')))));await DatabaseService.instance.updateShiftSchedule(s);await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');return 'original schedule restored';}})()""")
    # All these tables were empty before this explicit test session. Persist evidence first.
    snapshot('extended_cleanup_history_evidence')
    run('extended_cleanup_history','services/database_service.dart',"""(() async {final d=await DatabaseService.instance.database;for(final n in ['alarm_history','alarm_creation_log','alarm_overrides','condition_shift_times'])await d.delete(n);return 'temporary test records removed';})()""")
    sync_schedule()
    prefs=json.loads((OUT/'oct04_original_prefs.json').read_text(encoding='utf8'))
    run('extended_restore_presets','services/database_service.dart',"(() async {final p=await SharedPreferences.getInstance();await p.setString('custom_alarm_presets',"+json.dumps(prefs['custom_alarm_presets'])+");return 'original presets restored';})()")
    tab(2)
    run('extended_reload_presets','screens/calendar_tab.dart',"""(() {void visit(Element e){if(e is StatefulElement&&e.state is _CalendarTabState)(e.state as _CalendarTabState).ref.invalidate(customAlarmPresetsProvider);e.visitChildren(visit);}WidgetsBinding.instance.rootElement!.visitChildren(visit);return 'reloaded';})()""")
    snapshot('extended_after_cleanup')

if __name__=='__main__':
    connect_vm();adb('shell','input','keyevent','KEYCODE_WAKEUP');a=sys.argv[1]
    if a=='prep':tab(4);prep()
    elif a=='tap':tap(sys.argv[2])
    elif a=='key':tap(sys.argv[2],True)
    elif a=='labels':labels(sys.argv[2] if len(sys.argv)>2 else 'extended_labels')
    elif a=='clock':clock(int(sys.argv[2]),int(sys.argv[3]))
    elif a=='fixed':fixed()
    elif a=='fixed_add':fixed_add(int(sys.argv[2]),int(sys.argv[3]))
    elif a=='snapshot':snapshot(sys.argv[2])
    elif a=='clean':clean()
    else:raise ValueError(a)
