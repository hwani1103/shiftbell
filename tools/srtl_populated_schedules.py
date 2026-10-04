import os
"""Populated schedule timeline and create/edit sheets on both fold states."""
import time
from usb_audit_device import connect_vm,adb
from srtl_current_audit import ev,locale,fold,tab,push,back,invoke,inspect
from srtl_extra_layouts import bottom,keyboard

connect_vm();locale('ko-KR');tab(1)
ev('srtl_populate_twelve_schedules','screens/schedule_management_tab.dart',"""(() async {
  _ScheduleManagementTabState? s;void visit(Element e){if(e is StatefulElement && e.state is _ScheduleManagementTabState)s=e.state as _ScheduleManagementTabState;e.visitChildren(visit);}
  WidgetsBinding.instance.rootElement!.visitChildren(visit);
  final n=s!.ref.read(dateScheduleProvider.notifier);
  await n.forceReloadForDate('2026-10-03');
  for(final old in [...(s!.ref.read(dateScheduleProvider)['2026-10-03']??<DateSchedule>[])])await n.delete(old);
  for(var i=0;i<12;i++)await n.create(DateSchedule(date:'2026-10-03',
    content:['병원 진료와 검사 결과 상담 / Clinic follow-up','직장 동료와 안전교육 및 장비 점검 / Safety training','가족 식사 / Family meal'][i%3]+' ${i+1}',
    startMinutes:480+i*30,durationMinutes:i%3==0?null:90,
    color:kScheduleBlockColors[i%kScheduleBlockColors.length],iconIndex:i%5,styleIndex:i%8+1,
    fontIndex:i%5+1,createdAt:DateTime.now().toIso8601String()));
  return '12 real provider-created schedules, notifications off';
})()""")
for lang in ['ko-KR','en-US']:
    locale(lang)
    for opened in [False,True]:
        fold(opened)
        adb('shell','settings','put','system','font_scale',os.environ.get('SRTL_SCALE','1.3'));time.sleep(2)
        p=lang+('_open_' if opened else '_closed_')+'populated_schedules_'
        if lang=='ko-KR':tab(1)
        else:
            # This tab is not offered in the English navigation; inspect the
            # shared renderer separately without claiming a normal EN entry.
            push('screens/schedule_management_tab.dart','Scaffold(body:SafeArea(child:ScheduleManagementTab(onDisabled:(){},onConfirmed:() async {})))')
        inspect(p+'timeline');bottom(p+'timeline')
        invoke('screens/schedule_management_tab.dart','_TimeAxisPickerState','_openCreateSheet(540)')
        inspect(p+'create');keyboard(p+'create');bottom(p+'create');back()
        ev(p+'edit_existing','screens/schedule_management_tab.dart',"""(() async {
          _TimeAxisPickerState? s;void visit(Element e){if(e is StatefulElement && e.state is _TimeAxisPickerState)s=e.state as _TimeAxisPickerState;e.visitChildren(visit);}
          WidgetsBinding.instance.rootElement!.visitChildren(visit);
          await s!.ref.read(dateScheduleProvider.notifier).forceReloadForDate('2026-10-03');
          final item=s!.ref.read(dateScheduleProvider)['2026-10-03']!.first;
          showModalBottomSheet(context:s!.context,isScrollControlled:true,builder:(_)=>_CreateBlockSheet(startMinutes:item.startMinutes,dateKey:item.date,existing:item));
          return 'existing schedule edit draft';
        })()""")
        inspect(p+'edit');keyboard(p+'edit');bottom(p+'edit');back()
        if lang=='en-US':back()
adb('shell','settings','put','system','font_scale','1.0')
