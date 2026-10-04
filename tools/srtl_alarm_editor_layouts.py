import os
"""Nested alarm editors and horizontal popup scroll, KO/EN folded/unfolded."""
import time
from srtl_current_audit import ev,tab,fold,locale,invoke,inspect,back
from srtl_extra_layouts import bottom
from usb_audit_device import adb,connect_vm

connect_vm()
for lang in ['ko-KR','en-US']:
    locale(lang)
    for opened in [False,True]:
        fold(opened);adb('shell','settings','put','system','font_scale',os.environ.get('SRTL_SCALE','1.3'));time.sleep(.5)
        p=lang+('_open_' if opened else '_closed_')+'nested_'
        tab(2)
        invoke('screens/calendar_tab.dart','_CalendarTabState',
               '_showDayDetailPopup(DateTime(2026,10,3),s!.ref.read(scheduleProvider).value!)')
        ev(p+'horizontal_scroll','main.dart',"""(() {
          var count=0;void visit(Element e){
            if(e.widget is Offstage && (e.widget as Offstage).offstage)return;
            if(e is StatefulElement && e.state is ScrollableState){final p=(e.state as ScrollableState).position;
              if(p.hasContentDimensions && p.axis==Axis.horizontal && p.maxScrollExtent>0){p.jumpTo(p.maxScrollExtent);count++;}}
            e.visitChildren(visit);
          }WidgetsBinding.instance.rootElement!.visitChildren(visit);return '$count horizontal lists at end';
        })()""")
        inspect(p+'day_fifth_fixed_alarm');back()
        ev(p+'free_preset_slot','screens/calendar_tab.dart',"""(() async {
          _CalendarTabState? s;void visit(Element e){if(e is StatefulElement && e.state is _CalendarTabState)s=e.state as _CalendarTabState;e.visitChildren(visit);}
          WidgetsBinding.instance.rootElement!.visitChildren(visit);
          for(final a in await CustomAlarmService.instance.futureAssignments(4))await s!.ref.read(alarmNotifierProvider.notifier).deleteAlarm(a.id!,a.date!);
          return 'slot 4 assignment removed through alarm service';
        })()""")
        invoke('screens/calendar_tab.dart','_CalendarTabState','_selectAlarmPreset(4)')
        invoke('screens/calendar_tab.dart','_CalendarTabState','_editAlarmPreset(delete:false)')
        inspect(p+'one_touch_time_picker');bottom(p+'one_touch_time_picker');back()
        invoke('screens/calendar_tab.dart','_CalendarTabState','_backFromAlarmPanel()')
        ev(p+'restore_slot','screens/calendar_tab.dart',"""(() async {
          _CalendarTabState? s;void visit(Element e){if(e is StatefulElement && e.state is _CalendarTabState)s=e.state as _CalendarTabState;e.visitChildren(visit);}
          WidgetsBinding.instance.rootElement!.visitChildren(visit);
          final r=await CustomAlarmService.instance.assign(DateTime(2026,10,3),s!.ref.read(customAlarmPresetsProvider)[4],4);return r.result.toString();
        })()""")
        tab(4)
        invoke('screens/settings_tab.dart','_SettingsTabState','_showEditFixedAlarmsScreen()')
        invoke('screens/settings_tab.dart','_EditFixedAlarmsScreenState','_showAlarmEditDialog(s!.widget.shiftTypes.first)')
        inspect(p+'five_fixed_editor');bottom(p+'five_fixed_editor')
        invoke('screens/settings_tab.dart','_ShiftAlarmEditDialogState','_editAlarmTime(0)')
        inspect(p+'fixed_time_picker');bottom(p+'fixed_time_picker');back();back();back()
adb('shell','settings','put','system','font_scale','1.0')
