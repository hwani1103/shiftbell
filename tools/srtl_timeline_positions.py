import os
"""Inspect populated, not empty, positions of the 12-event timeline."""
import time
from usb_audit_device import connect_vm,adb
from srtl_current_audit import locale,fold,tab,push,back,ev,inspect
connect_vm()
for lang in ['ko-KR','en-US']:
    locale(lang)
    for opened in [False,True]:
        fold(opened);adb('shell','settings','put','system','font_scale',os.environ.get('SRTL_SCALE','1.3'));time.sleep(1)
        if lang=='ko-KR':tab(1)
        else:push('screens/schedule_management_tab.dart','Scaffold(body:SafeArea(child:ScheduleManagementTab(onDisabled:(){},onConfirmed:() async {})))')
        for minute in [480,600,750]:
            ev('timeline_at_'+str(minute),'screens/schedule_management_tab.dart',"""(() {
              _TimeAxisPickerState? s;void visit(Element e){if(e.widget is Offstage && (e.widget as Offstage).offstage)return;if(e is StatefulElement && e.state is _TimeAxisPickerState)s=e.state as _TimeAxisPickerState;e.visitChildren(visit);}
              WidgetsBinding.instance.rootElement!.visitChildren(visit);
              if(s!._blocks.length!=12)throw StateError('12 events required');
              final p=(s!._yForMinutes(MINUTE)-16).clamp(0.0,s!._controller.position.maxScrollExtent).toDouble();
              s!._controller.jumpTo(p);s!._virtualOffset=p;return '12 events, visible position MINUTE';
            })()""".replace('MINUTE',str(minute)))
            inspect(lang+('_open_' if opened else '_closed_')+'timeline_populated_'+str(minute))
        if lang=='en-US':back()
adb('shell','settings','put','system','font_scale','1.0')
