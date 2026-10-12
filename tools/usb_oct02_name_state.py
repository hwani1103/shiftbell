import sys,json,base64
from usb_audit_device import evaluate,OUT
action=sys.argv[1]
notify="""void visit(Element e){if(e is StatefulElement && e.state is _SettingsTabState){
(e.state as _SettingsTabState).ref.read(scheduleProvider.notifier).applyExternallyPersisted(s);}
e.visitChildren(visit);} WidgetsBinding.instance.rootElement!.visitChildren(visit);"""
if action=='sync':
 body="final s=(await DatabaseService.instance.getShiftSchedule())!;"+notify+"return 'UI synchronized from persisted schedule';"
elif action=='assign':
 body="""final current=(await DatabaseService.instance.getShiftSchedule())!;
 if(!current.shiftTypes.contains('AuditTemp') || current.shiftTypes.length!=7) throw StateError('added name not persisted');
 final days={...?current.assignedDates,'2026-10-05':'AuditTemp'};
 final s=ShiftSchedule.fromMap({...current.toMap(),'assigned_dates':jsonEncode(days)});
 await DatabaseService.instance.updateShiftSchedule(s);
 """+notify+" return 'PASS added name; dated assignment prepared';"
elif action=='release':
 body="""final current=(await DatabaseService.instance.getShiftSchedule())!;
 if(!current.shiftTypes.contains('ExtraTemp') || current.assignedDates!['2026-10-05']!='ExtraTemp') throw StateError('rename did not update assignment');
 final s=ShiftSchedule.fromMap({...current.toMap(),'assigned_dates':'{}'});
 await DatabaseService.instance.updateShiftSchedule(s);
 """+notify+" return 'PASS rename propagated; temporary assignment cleared';"
elif action=='finish':
 original=json.loads(json.loads((OUT/'export_oct02_original.vm.json').read_text(encoding='utf-8'))['valueAsString'])['tables']['shift_schedule'][0]
 encoded=base64.b64encode(json.dumps(original,ensure_ascii=False).encode()).decode()
 body=f"""final current=(await DatabaseService.instance.getShiftSchedule())!;
 if(current.shiftTypes.contains('ExtraTemp') || current.shiftTypes.length!=6) throw StateError('unused deletion not persisted');
 final s=ShiftSchedule.fromMap(Map<String,dynamic>.from(jsonDecode(utf8.decode(base64Decode('{encoded}')))));
 await DatabaseService.instance.updateShiftSchedule(s);
 """+notify+"await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait'); return 'PASS unused deletion; original schedule and UI restored';"
else:raise ValueError(action)
evaluate('names_'+action,'screens/settings_tab.dart',('(() async {'+body+'})()').replace('\n',' '))
