import os
"""Exercise reordered setup choices with real taps, retaining only draft changes."""
import time
from usb_audit_device import connect_vm, adb
from usb_team_rules_audit import tap,key
from srtl_current_audit import locale,fold,tab,push,back,inspect,ev
from srtl_extra_layouts import bottom

connect_vm()
for lang in ['ko-KR','en-US']:
    locale(lang)
    for opened in [False,True]:
        fold(opened)
        for scale in os.environ.get('SRTL_SCALES','1.0,1.3').split(','):
            adb('shell','settings','put','system','font_scale',scale);time.sleep(2)
            p=lang+('_open_' if opened else '_closed_')+'setup_v2_'+scale+'_'
            push('screens/all_teams_setup_screen.dart',
                 "AllTeamsSetupScreen(pattern:"+ ("['주간','주간','휴무','휴무','야간집중근무','야간집중근무','휴무','휴무']" if lang=='ko-KR' else "['Day','Day','Off','Off','Late Night Shift','Late Night Shift','Off','Off']") +",myTodayIndex:4)")
            inspect(p+'names_first')
            tap('choose_C',"e.widget is AppShiftChip && (e.widget as AppShiftChip).label=='C' && (e.widget as AppShiftChip).onTap!=null")
            ev(p+'default_mode','screens/all_teams_setup_screen.dart',"""(() {
              _AllTeamsSetupScreenState? s;void visit(Element e){if(e is StatefulElement && e.state is _AllTeamsSetupScreenState)s=e.state as _AllTeamsSetupScreenState;e.visitChildren(visit);}
              WidgetsBinding.instance.rootElement!.visitChildren(visit);
              if(s!._individual || s!._myTeamEntry!.name!='C')throw StateError('Wrong default');return 'shared selected, C retained';
            })()""")
            key('team-mode-shared');inspect(p+'shared_selected');bottom(p+'shared_assignment')
            key('team-mode-individual');inspect(p+'individual_selected');bottom(p+'individual_rules')
            key('team-mode-shared')
            ev(p+'switch_back','screens/all_teams_setup_screen.dart',"""(() {
              _AllTeamsSetupScreenState? s;void visit(Element e){if(e is StatefulElement && e.state is _AllTeamsSetupScreenState)s=e.state as _AllTeamsSetupScreenState;e.visitChildren(visit);}
              WidgetsBinding.instance.rootElement!.visitChildren(visit);
              if(s!._individual || s!._myTeamEntry!.name!='C' || s!._assignments[s!._myTeamEntry]!=4)throw StateError('Selection lost');return 'switch retains own position';
            })()""")
            back()
adb('shell','settings','put','system','font_scale','1.0')
