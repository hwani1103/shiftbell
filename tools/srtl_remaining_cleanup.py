"""End this synthetic SRTL session without leaving future alarms behind."""
from usb_audit_device import connect_vm, adb, compare_os
from srtl_current_audit import ev, locale, tab

connect_vm()
ev('cleanup_return_to_main', 'main.dart', """(() async {
 await Future<void>.delayed(Duration.zero);
 NavigatorState? nav;void visit(Element e){if(e is StatefulElement && e.state is NavigatorState)nav=e.state as NavigatorState;e.visitChildren(visit);}
 WidgetsBinding.instance.rootElement!.visitChildren(visit);
 nav!.popUntil((r)=>r.isFirst);return 'main route';
})()""")
locale('ko-KR')
ev('cleanup_calendar_navigation', 'main.dart', """(() {
 BottomNavigationBar? bar;void visit(Element e){if(e.widget is BottomNavigationBar)bar=e.widget as BottomNavigationBar;e.visitChildren(visit);}
 WidgetsBinding.instance.rootElement!.visitChildren(visit);
 final i=bar!.items.indexWhere((item)=>['달력','Calendar'].contains(item.label));
 if(i<0)throw StateError('Calendar tab missing');bar!.onTap!(i);return 'calendar navigation callback';
})()""")
import time
time.sleep(.8)
ev('cleanup_synthetic_future_alarms', 'screens/calendar_tab.dart', """(() async {
 _CalendarTabState? s;void visit(Element e){if(e is StatefulElement && e.state is _CalendarTabState)s=e.state as _CalendarTabState;e.visitChildren(visit);}
 WidgetsBinding.instance.rootElement!.visitChildren(visit);
 await s!.ref.read(alarmNotifierProvider.notifier).deleteAllAlarmsCompletely();
 return 'synthetic alarm rows and templates cleared through production service';
})()""")
assert compare_os('cleanup_zero_alarms')
ev('cleanup_zero_database', 'services/database_service.dart', """(() async {
 final d=await DatabaseService.instance.database;final rows=await d.query('alarms');
 if(rows.isNotEmpty)throw StateError('Synthetic alarms remain');return 'DB alarms=0';
})()""")
adb('shell','settings','put','system','font_scale','1.0')
print('Cleanup complete: no future alarms, font scale 1.0, Korean main calendar.')
