import sys
from usb_audit_device import evaluate,compare_os

reverse=sys.argv[1]=='restore'
mapping="{'Afternoon Shift':'주간','WWWWWWWWWWWWWWWW':'야간','휴무일정추가':'휴무'}" if reverse else "{'주간':'Afternoon Shift','야간':'WWWWWWWWWWWWWWWW','휴무':'휴무일정추가'}"
result=evaluate('long_names_'+sys.argv[1], 'screens/settings_tab.dart', ("""(() async {
 _SettingsTabState? state;void visit(Element e){if(e is StatefulElement && e.state is _SettingsTabState)state=e.state as _SettingsTabState;e.visitChildren(visit);}
 WidgetsBinding.instance.rootElement!.visitChildren(visit);
 if(state==null)throw StateError('open settings first');
 final s=(await DatabaseService.instance.getShiftSchedule())!;
 final mapping=MAP;
 if(!mapping.keys.every(s.shiftTypes.contains))throw StateError('unexpected fixture');
 await state!._applyShiftNameChanges(s,ShiftNameEdits(mapping,{},[]));
 final after=(await DatabaseService.instance.getShiftSchedule())!;
 if(!mapping.values.every(after.shiftTypes.contains))throw StateError('rename failed');
 return 'PASS rename and references persisted';
 })()""".replace('MAP',mapping)).replace('\n',' '))
assert compare_os('long_names_'+sys.argv[1]+'_os')
