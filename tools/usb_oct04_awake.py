"""Targeted USB checks. Explicit serial, private evidence, no fixture replacement."""
import json, os, sys, time, re
import xml.etree.ElementTree as ET
assert os.environ.get('SHIFTBELL_AUDIT_SERIAL') == 'R5KL20DHWAE'
from usb_audit_device import adb, OUT, connect_vm, evaluate, compare_os, capture
from srtl_current_audit import ev, push, back, tab

def texts():
    adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
    raw=adb('exec-out','cat','/sdcard/usb_audit_ui.xml')
    (OUT/'current_ui.xml').write_bytes(raw)
    return ET.fromstring(raw)

def tap(label):
    nodes=[n for n in texts().iter('node') if (n.get('text') or n.get('content-desc'))==label]
    assert len(nodes)==1,(label,len(nodes))
    x1,y1,x2,y2=map(int,re.findall(r'\d+',nodes[0].get('bounds')))
    adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));time.sleep(.6)

action=sys.argv[1]
adb('shell','input','keyevent','KEYCODE_WAKEUP')
connect_vm()
if action=='baseline':
    assert not (OUT/'oct04_original_tables.json').exists()
    data=evaluate('export_oct04_original_tables','services/database_service.dart',"""(() async {
      final d=await DatabaseService.instance.database;final names=await d.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
      final result=<String,dynamic>{};for(final row in names){final n=row['name'] as String;result[n]=await d.query(n,orderBy:'rowid');}return jsonEncode(result);
    })()""".replace('\n',' '))
    (OUT/'oct04_original_tables.json').write_text(data,encoding='utf8')
    prefs=evaluate('export_oct04_original_prefs','services/database_service.dart',"""(() async {final p=await SharedPreferences.getInstance();return jsonEncode({for(final k in p.getKeys()) k:p.get(k)});})()""")
    (OUT/'oct04_original_prefs.json').write_text(prefs,encoding='utf8')
    print('Table counts:',{k:len(v) for k,v in json.loads(data).items()})
    compare_os('oct04_original_os')
elif action=='work':push('screens/work_hours_settings_screen.dart','WorkHoursSettingsScreen()')
elif action=='texts':
    for n in texts().iter('node'):
        s=n.get('text') or n.get('content-desc')
        if s:print(repr(s),n.get('bounds'))
elif action=='tap':tap(sys.argv[2])
elif action in ('key','text_tap'):
    value=json.dumps(sys.argv[2],ensure_ascii=False)
    condition='e.widget.key==ValueKey(VALUE)' if action=='key' else '(e.widget is Text && (e.widget as Text).data==VALUE)'
    result=ev('physical_'+action,'main.dart',("""(() {final found=<String>[];void visit(Element e){if(e.widget is Offstage && (e.widget as Offstage).offstage)return;if(CONDITION){final b=e.findRenderObject();if(b is RenderBox && b.hasSize){final p=b.localToGlobal(b.size.center(Offset.zero));final d=View.of(e).devicePixelRatio;found.add('${(p.dx*d).round()},${(p.dy*d).round()}');}}e.visitChildren(visit);}WidgetsBinding.instance.rootElement!.visitChildren(visit);if(found.length!=1)throw StateError('matches=${found.length}');return found.single;})()""").replace('CONDITION',condition).replace('VALUE',value))
    adb('shell','input','tap',*result.split(','));time.sleep(.7)
elif action=='calendar_state':
    ev(sys.argv[2],'screens/calendar_tab.dart',"""(() { _CalendarTabState? s;int dialogs=0;void visit(Element e){if(e.widget is Offstage && (e.widget as Offstage).offstage)return;if(e is StatefulElement && e.state is _CalendarTabState)s=e.state as _CalendarTabState;if(e.widget is Dialog)dialogs++;e.visitChildren(visit);}WidgetsBinding.instance.rootElement!.visitChildren(visit);return 'panel=${s!._alarmPanelOpen},slot=${s!._assignPresetIndex},dialogs=$dialogs,presets=${s!.ref.read(customAlarmPresetsProvider).map((p)=>p.time).join(",")}';})()""")
elif action=='time':
    delta=int(sys.argv[2])
    ev('prepare_time_'+str(delta),'widgets/alarm_time_editor.dart',"""(() {AlarmTimePickerState? s;void visit(Element e){if(e is StatefulElement && e.state is AlarmTimePickerState)s=e.state as AlarmTimePickerState;e.visitChildren(visit);}WidgetsBinding.instance.rootElement!.visitChildren(visit);final target=DateTime.now().add(Duration(minutes:DELTA));s!.setState((){s!._hour=target.hour;s!._minute=target.minute;});return '${target.hour}:${target.minute}';})()""".replace('DELTA',str(delta)))
elif action=='flutter_texts':
    ev('visible_texts','main.dart',"""(() {final values=<String>[];void visit(Element e){if(e.widget is Offstage && (e.widget as Offstage).offstage)return;if(e.widget is Text){final w=e.widget as Text;final v=w.data??w.textSpan?.toPlainText();if(v!=null)values.add(v);}e.visitChildren(visit);}WidgetsBinding.instance.rootElement!.visitChildren(visit);return values.join('|');})()""")
elif action=='alarms':compare_os(sys.argv[2])
elif action=='reuse_snapshot':
    data=evaluate('export_'+sys.argv[2],'services/database_service.dart',"(() async {final d=await DatabaseService.instance.database;return jsonEncode({'alarms':await d.query('alarms',orderBy:'id'),'history':await d.query('alarm_history',orderBy:'id'),'creation':await d.query('alarm_creation_log',orderBy:'id')});})()")
    (OUT/(sys.argv[2]+'.json')).write_text(data,encoding='utf8')
elif action=='clean_trial':
    ident=int(sys.argv[2]);before=json.loads((OUT/'oct04_original_tables.json').read_text(encoding='utf8'))
    assert ident not in {r['id'] for r in before['alarms']}
    evaluate('trial_history_export','services/database_service.dart',f"(() async {{final d=await DatabaseService.instance.database;return jsonEncode({{'history':await d.query('alarm_history',where:'alarm_id=?',whereArgs:[{ident}]),'creation':await d.query('alarm_creation_log',where:'alarm_id=?',whereArgs:[{ident}])}});}})()")
    evaluate('trial_history_cleanup','services/database_service.dart',f"(() async {{final d=await DatabaseService.instance.database;if((await d.query('alarms',where:'id=?',whereArgs:[{ident}])).isNotEmpty)throw StateError('trial alarm still exists');await d.delete('alarm_history',where:'alarm_id=?',whereArgs:[{ident}]);await d.delete('alarm_creation_log',where:'alarm_id=?',whereArgs:[{ident}]);return 'only trial history removed';}})()")
    old=json.loads((OUT/'oct04_original_prefs.json').read_text(encoding='utf8'))
    key='custom_alarm_presets';value=old.get(key)
    expr=f'await p.setString({json.dumps(key)},{json.dumps(value)});' if value is not None else f'await p.remove({json.dumps(key)});'
    evaluate('restore_original_presets','services/database_service.dart','(() async {final p=await SharedPreferences.getInstance();'+expr+"return 'original presets restored';})()")
    ev('reload_original_presets','screens/calendar_tab.dart',"""(() {_CalendarTabState? s;void visit(Element e){if(e is StatefulElement && e.state is _CalendarTabState)s=e.state as _CalendarTabState;e.visitChildren(visit);}WidgetsBinding.instance.rootElement!.visitChildren(visit);s!.ref.invalidate(customAlarmPresetsProvider);return 'reloaded';})()""")
elif action=='bottom':
    ev('bottom','main.dart',"""(() {void visit(Element e){if(e.widget.runtimeType.toString()=='TappableNumberPicker')return;if(e.widget is Offstage && (e.widget as Offstage).offstage)return;if(e is StatefulElement && e.state is ScrollableState){final p=(e.state as ScrollableState).position;if(p.hasContentDimensions && p.axis==Axis.vertical && p.maxScrollExtent.isFinite)p.jumpTo(p.maxScrollExtent);}e.visitChildren(visit);}WidgetsBinding.instance.rootElement!.visitChildren(visit);return 'bottom';})()""")
elif action=='back':back()
elif action=='tab':tab(int(sys.argv[2]))
elif action=='capture':capture(sys.argv[2])
elif action=='work_state':
    ev(sys.argv[2],'screens/work_hours_settings_screen.dart',"""(() {ConsumerState? s;void visit(Element e){if(e is StatefulElement && e.widget is WorkHoursSettingsScreen)s=e.state as ConsumerState;e.visitChildren(visit);}WidgetsBinding.instance.rootElement!.visitChildren(visit);final v=s!.ref.read(workHoursSettingsProvider);return '${v.periodMode.name}|${v.paydayCutoffDay}|${v.cutoffAnchor.name}|${v.periodRangeShort(DateTime.now())}';})()""")
elif action=='restore_work':
    old=json.loads((OUT/'oct04_original_prefs.json').read_text(encoding='utf8'))
    keys=['work_hours_period_mode','work_hours_payday_cutoff_day','work_hours_cutoff_anchor']
    lines=['final p=await SharedPreferences.getInstance();']
    for k in keys:
        value=old.get(k)
        if value is None:lines.append(f'await p.remove({json.dumps(k)});')
        elif isinstance(value,int):lines.append(f'await p.setInt({json.dumps(k)},{value});')
        else:lines.append(f'await p.setString({json.dumps(k)},{json.dumps(value)});')
    evaluate('work_restore_prefs','services/database_service.dart','(() async {'+''.join(lines)+"return 'original work preferences restored';})()")
    ev('work_restore_provider','screens/work_hours_settings_screen.dart',"""(() async {ConsumerState? s;void visit(Element e){if(e is StatefulElement && e.widget is WorkHoursSettingsScreen)s=e.state as ConsumerState;e.visitChildren(visit);}WidgetsBinding.instance.rootElement!.visitChildren(visit);s!.ref.invalidate(workHoursSettingsProvider);return 'provider reload';})()""")
elif action=='verify':
    data=evaluate('export_oct04_final_tables','services/database_service.dart',"""(() async {final d=await DatabaseService.instance.database;final names=await d.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");final result=<String,dynamic>{};for(final row in names){final n=row['name'] as String;result[n]=await d.query(n,orderBy:'rowid');}return jsonEncode(result);})()""")
    (OUT/'oct04_final_tables.json').write_text(data,encoding='utf8')
    before=json.loads((OUT/'oct04_original_tables.json').read_text(encoding='utf8'));after=json.loads(data)
    changed=[k for k in set(before)|set(after) if before.get(k)!=after.get(k)]
    print('Changed tables:',changed)
    assert not changed, 'Original device tables have not been restored'
    compare_os('oct04_final_os')
