import os
"""Verify only the final safe-area and word-wrap changes."""
import time
from usb_audit_device import connect_vm,adb
from srtl_current_audit import locale,fold,tab,invoke,inspect,back,ev
from srtl_extra_layouts import bottom
connect_vm()
for lang in ['ko-KR','en-US']:
    locale(lang)
    for opened in [False,True]:
        fold(opened);adb('shell','settings','put','system','font_scale',os.environ.get('SRTL_SCALE','1.3'));time.sleep(1)
        p=lang+('_open_' if opened else '_closed_')+'final_fixes_'
        tab(4);invoke('screens/settings_tab.dart','_SettingsTabState','_showAlarmTypeDialog()')
        inspect(p+'sound_safearea');bottom(p+'sound_safearea');back()
        tab(2)
        ev(p+'free_slot','screens/calendar_tab.dart',"""(() async {
          _CalendarTabState? s;void visit(Element e){if(e is StatefulElement && e.state is _CalendarTabState)s=e.state as _CalendarTabState;e.visitChildren(visit);}
          WidgetsBinding.instance.rootElement!.visitChildren(visit);
          for(final a in await CustomAlarmService.instance.futureAssignments(4))await s!.ref.read(alarmNotifierProvider.notifier).deleteAlarm(a.id!,a.date!);
          return 'synthetic slot free';
        })()""")
        invoke('screens/calendar_tab.dart','_CalendarTabState','_selectAlarmPreset(4)')
        invoke('screens/calendar_tab.dart','_CalendarTabState','_editAlarmPreset(delete:false)')
        inspect(p+'one_touch_words');bottom(p+'one_touch_words');back()
        invoke('screens/calendar_tab.dart','_CalendarTabState','_backFromAlarmPanel()')
adb('shell','settings','put','system','font_scale','1.0')
