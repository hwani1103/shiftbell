"""Configured roster scroll limits and both editing modes; confirmations cancelled."""
import os,time
from usb_audit_device import connect_vm,adb
from srtl_current_audit import ev,locale,fold,tab,push,back,inspect,invoke
from srtl_extra_layouts import bottom
from srtl_numbered_captures import seed
from usb_team_rules_audit import key,tap
connect_vm()
for lang in ['ko-KR','en-US']:
    locale(lang);tab(2)
    for mode in ['common','individual']:
        seed(lang,mode)
        for opened in [False,True]:
            fold(opened);adb('shell','settings','put','system','font_scale',os.environ.get('SRTL_SCALE','1.3'));time.sleep(.7)
            p=lang+('_open_' if opened else '_closed_')+mode+'_detail_'
            push('screens/all_shifts_view.dart','AllShiftsView()')
            bottom(p+'roster')
            ev(p+'dates_end','main.dart',"""(() {
              var n=0;void visit(Element e){if(e.widget is Offstage && (e.widget as Offstage).offstage)return;
                if(e is StatefulElement && e.state is ScrollableState){final p=(e.state as ScrollableState).position;
                  if(p.hasContentDimensions && p.axis==Axis.horizontal && p.maxScrollExtent.isFinite){p.jumpTo(p.maxScrollExtent);n++;}}
                e.visitChildren(visit);
              }WidgetsBinding.instance.rootElement!.visitChildren(visit);return '$n horizontal scrolls at end';
            })()""")
            inspect(p+'last_dates')
            if os.environ.get('SRTL_DETAIL_SCROLL_ONLY')=='1':
                back()
                continue
            tap(p+'edit',"e.widget is Icon && (e.widget as Icon).icon==Icons.edit_outlined")
            inspect(p+'choices');key('team-edit-switch');inspect(p+'teams')
            key('team-switch-slot-0' if mode=='common' else 'team-switch-'+('가' if lang=='ko-KR' else 'A'))
            inspect(p+'selected');bottom(p+'selected')
            invoke('screens/team_schedule_edit_screen.dart','_TeamScheduleEditScreenState','_save()')
            inspect(p+'confirmation');bottom(p+'confirmation');back()
            key('team-edit-recreate');inspect(p+'recreate');back();back();back()
adb('shell','settings','put','system','font_scale','1.0')
