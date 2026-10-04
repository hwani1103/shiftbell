"""Actual common-pattern creation, restricted chips, switch and recreation UI."""
import time
from usb_team_rules_audit import setup_fixture,open_calendar_roster,button,tap,key
from usb_audit_device import connect_vm,capture,compare_os
from usb_audit_scenarios import scenario
from srtl_current_audit import tab,ev,back

connect_vm();tab(2);setup_fixture();open_calendar_roster()
button('전체 교대조 근무표 만들기')
tap('common_my_C',"e.widget is AppShiftChip && (e.widget as AppShiftChip).label=='C' && (e.widget as AppShiftChip).onTap!=null")
for team,slot in [('A',0),('B',2),('D',6)]:
    tap('common_pick_'+team,"e.widget is AppShiftChip && (e.widget as AppShiftChip).label=='"+team+"' && (e.widget as AppShiftChip).onTap!=null")
    key('team-assign-slot-'+str(slot))
capture('common_fully_assigned');button('저장');capture('common_review');key('team-review-save');time.sleep(1)
scenario('common_created','services/database_service.dart',"""
 final c=(await DatabaseService.instance.getTeamScheduleConfig())!;
 check(!c.individual && c.myTeam=='C','default shared mode saved');
 final now=DateTime.now();for(final e in {'A':0,'B':2,'C':4,'D':6}.entries)check(c.indexOn(e.key,now,8)==e.value,'correct index '+e.key);
""")
before=ev('common_before','services/database_service.dart',"(() async {final c=(await DatabaseService.instance.getTeamScheduleConfig())!;return jsonEncode(c.toJson());})()")
tap('common_edit',"e.widget is Icon && (e.widget as Icon).icon==Icons.edit_outlined")
key('team-edit-switch')
scenario('common_restricted_slots','screens/team_schedule_edit_screen.dart',"""
 final chips=<TeamAssignmentChip>[];void visit(Element e){if(e.widget is TeamAssignmentChip)chips.add(e.widget as TeamAssignmentChip);e.visitChildren(visit);}
 WidgetsBinding.instance.rootElement!.visitChildren(visit);
 final visible=chips.where((c)=>c.key.toString().contains('team-switch-slot')).toList();
 check(visible.length==8,'eight positions');
 for(final c in visible)check((c.onTap!=null)==[0,2,6].contains(c.index),'only other assigned team selectable '+c.index.toString());
""")
key('team-switch-slot-0');capture('common_switch_A');button('저장');capture('common_switch_confirmation');button('취소')
scenario('common_switch_cancel','services/database_service.dart',"check((await DatabaseService.instance.getTeamScheduleConfig())!.myTeam=='C','cancel retains current team');")
button('저장');button('확인');time.sleep(1)
scenario('common_switch_saved','services/database_service.dart',"""
 final s=DatabaseService.instance;final c=(await s.getTeamScheduleConfig())!;final m=(await s.getShiftSchedule())!;
 check(!c.individual && c.myTeam=='A','team switched, mode retained');
 final now=DateTime.now();for(var i=-20;i<30;i++){final date=DateTime(now.year,now.month,now.day+i);check(m.getShiftForDate(date)==c.rules['A']!.shiftOn(date),'date '+i.toString());}
 for(final e in {'A':0,'B':2,'C':4,'D':6}.entries)check(c.indexOn(e.key,now,8)==e.value,'fixed team index '+e.key);
 final d=await s.database;check((await d.query('alarm_history',where:'alarm_id=?',whereArgs:[987654])).length==1,'history retained');
""")
assert compare_os('common_switch_os')
capture('common_roster_A_highlight')
main=ev('common_before_recreate','services/database_service.dart',"(() async {return jsonEncode((await DatabaseService.instance.getShiftSchedule())!.toMap());})()")
tap('common_edit_again',"e.widget is Icon && (e.widget as Icon).icon==Icons.edit_outlined")
key('team-edit-recreate');capture('common_recreate_warning');button('취소')
scenario('recreate_cancel','services/database_service.dart',"check(await DatabaseService.instance.getTeamScheduleConfig()!=null,'recreate cancel retains roster');")
key('team-edit-recreate');button('확인');time.sleep(.6)
scenario('recreate_confirm','services/database_service.dart',"check(await DatabaseService.instance.getTeamScheduleConfig()==null,'recreate clears roster');")
after=ev('common_after_recreate','services/database_service.dart',"(() async {return jsonEncode((await DatabaseService.instance.getShiftSchedule())!.toMap());})()")
assert main==after,'Recreation must preserve main calendar'
capture('recreate_initial_setup');back();back();tab(2)
print('PASS common UI creation / cancel / switch / immutable indices / recreate.')
