"""Populated sleep UI. English sleep is not connected to the current app."""
import os,time
from usb_audit_device import connect_vm,adb
from srtl_current_audit import ev,locale,fold,tab,push,back,inspect
from srtl_extra_layouts import bottom
connect_vm()
ev('sleep_fixture','services/database_service.dart',"""(() async {
  final s=DatabaseService.instance;final d=await s.database;await d.delete('sleep_records');
  final today=DateTime.now();
  for(var i=0;i<12;i++){
    final end=DateTime(today.year,today.month,today.day-i,7,15);
    await s.insertSleepRecord(SleepRecord(start:end.subtract(Duration(hours:5+i%4)),end:end,
      source:SleepSource.manual,status:SleepStatus.confirmed));
  }
  for(var i=0;i<3;i++){
    final end=DateTime(today.year,today.month,today.day-i,14);
    await s.insertSleepRecord(SleepRecord(start:end.subtract(const Duration(hours:1)),end:end,
      source:SleepSource.autoDetected,status:SleepStatus.pendingConfirmation,confidence:SleepConfidence.low));
  }return '12 confirmed and 3 pending synthetic sleep records';
})()""")
for lang in ['ko-KR']:
    locale(lang)
    for opened in [False,True]:
        fold(opened);adb('shell','settings','put','system','font_scale',os.environ.get('SRTL_SCALE','1.3'));time.sleep(1)
        p=lang+('_open_' if opened else '_closed_')+'sleep_'
        if lang=='ko-KR':tab(3)
        else:push('screens/english_condition_tab.dart','EnglishConditionTab(onDisabled:(){},onConfirmed:() async {})')
        ev(p+'refresh','screens/condition_tab.dart',"""(() async {
          BuildContext? c;void visit(Element e){if(e.widget is Scaffold)c=e;e.visitChildren(visit);}
          WidgetsBinding.instance.rootElement!.visitChildren(visit);
          await ProviderScope.containerOf(c!,listen:false).read(sleepRecordProvider.notifier).refresh();
          return 'shared sleep provider refreshed';
        })()""")
        inspect(p+'top');bottom(p+'all_content')
        if lang=='ko-KR':
            push('screens/sleep_calendar_full_screen.dart','SleepCalendarFullScreen()')
            inspect(p+'calendar');bottom(p+'calendar');back()
            ev(p+'edit','widgets/sleep_edit_dialog.dart',"""(() {
              BuildContext? context;void visit(Element e){if(e.widget is Offstage && (e.widget as Offstage).offstage)return;if(e.widget is Scaffold)context=e;e.visitChildren(visit);}
              WidgetsBinding.instance.rootElement!.visitChildren(visit);
              showSleepSlotEditDialog(context!,initialStart:DateTime(2026,10,2,23),initialEnd:DateTime(2026,10,3,7),showDeleteButton:true);return 'sleep editor';
            })()""")
            time.sleep(.5);inspect(p+'edit');bottom(p+'edit');back()
        else:back()
adb('shell','settings','put','system','font_scale','1.0')
