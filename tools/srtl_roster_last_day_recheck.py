"""Re-scroll after each scale change; changing cell widths can move the last day offscreen."""
import os, time
from usb_audit_device import connect_vm, adb
from srtl_current_audit import locale, fold, push, back, ev, inspect, invoke
from usb_team_rules_audit import key, tap

connect_vm()
os.environ.pop('SRTL_INSPECT_SCALES', None)
for lang in ['ko-KR','en-US']:
    locale(lang)
    for opened in [False, True]:
        fold(opened)
        push('screens/all_shifts_view.dart','AllShiftsView()')
        for scale in ['1.0','1.3']:
            adb('shell','settings','put','system','font_scale',scale);time.sleep(.7)
            name=lang+('_open_' if opened else '_closed_')+'roster_last_day_recheck_'+scale
            ev(name+'_end','main.dart',"""(() {
              final result=<String>[];
              void visit(Element e){
                if(e.widget is Offstage && (e.widget as Offstage).offstage)return;
                if(e.widget is TickerMode && !(e.widget as TickerMode).enabled)return;
                if(e is StatefulElement && e.state is ScrollableState){final p=(e.state as ScrollableState).position;
                  if(p.hasContentDimensions && p.maxScrollExtent.isFinite){p.jumpTo(p.maxScrollExtent);result.add('${p.axis}:${p.pixels}/${p.maxScrollExtent}');}}
                e.visitChildren(visit);
              }WidgetsBinding.instance.rootElement!.visitChildren(visit);return result.join(',');
            })()""")
            inspect(name)
        if lang=='en-US':
            tap('english_edit_recheck',"e.widget is Icon && (e.widget as Icon).icon==Icons.edit_outlined")
            inspect(lang+('_open_' if opened else '_closed_')+'edit_example_fixed_1.3')
            key('team-edit-switch');key('team-switch-A')
            invoke('screens/team_schedule_edit_screen.dart','_TeamScheduleEditScreenState','_save()')
            inspect(lang+('_open_' if opened else '_closed_')+'edit_confirmation_fixed_1.3')
            back();back()
        back()
adb('shell','settings','put','system','font_scale','1.0')
