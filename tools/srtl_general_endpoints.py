"""Finish only outstanding general screens; endpoints per updated user policy.

UI operations are sequential. Each screen stays open for its scale sweep.
Completion records require both initial and scroll-end inspection to finish.
"""
import json, os, time
from datetime import datetime
from pathlib import Path
from usb_audit_device import connect_vm, adb, OUT
from srtl_current_audit import ev, locale, fold, tab, push, back, inspect, invoke, fixture
from srtl_extra_layouts import bottom
from srtl_numbered_captures import seed

assert os.environ['SHIFTBELL_AUDIT_SERIAL']=='localhost:43845'
deadline=datetime(2026,10,3,23,11)
progress=OUT/'general_progress.json'
done=json.loads(progress.read_text(encoding='utf8')) if progress.exists() else []
def record(lang,opened,scene,scales):
    row={'language':lang,'posture':'open' if opened else 'closed','scene':scene,'scales':scales,'completed':datetime.now().isoformat()}
    done.append(row);progress.write_text(json.dumps(done,ensure_ascii=False,indent=2),encoding='utf8');print('COMPLETE',row,flush=True)

def scales_for(lang,opened,scene):
    scales=['1.0','1.3']
    # Completed in the previous EBBB session; source changes since then only
    # concerned onboarding and team-edit labels/card clipping.
    if (lang=='ko-KR' and not opened) or (lang=='en-US' and not opened and scene=='next_alarm'):
        scales.remove('1.3')
    for row in done:
        if row['language']==lang and row['posture']==('open' if opened else 'closed') and row['scene']==scene:
            scales=[s for s in scales if s not in row['scales']]
    return scales

def check_time():
    if datetime.now()>=deadline:raise TimeoutError('Lease reserve reached: unchecked screens remain incomplete')

def measure(lang,opened,scene):
    scales=scales_for(lang,opened,scene)
    os.environ['SRTL_INSPECT_SCALES']=','.join(scales)
    name=lang+('_open_' if opened else '_closed_')+'general_'+scene
    inspect(name);bottom(name)
    record(lang,opened,scene,scales)

connect_vm()
if not (OUT/'fixture_ready.txt').exists():
    fixture()
    (OUT/'fixture_ready.txt').write_text('Base fixture initialized',encoding='utf8')

routes=[('history','all_alarms_history_view','AllAlarmsHistoryView'),
        ('memos','memo_list_view','MemoListView'),
        ('work_hours','work_hours_settings_screen','WorkHoursSettingsScreen'),
        ('theme_picker','calendar_theme_picker_screen','CalendarThemePickerScreen'),
        ('help','help_screen','HelpScreen'),
        ('privacy','privacy_policy_screen','PrivacyPolicyScreen')]
dialogs=[('schedule_change','_showChangeScheduleDialog()'),
         ('shift_names','_showEditShiftNamesDialog()'),
         ('shift_colors','_showEditShiftColorsDialog()')]

# This suite verifies layout, not remote-coordinate input delivery. Fold changes
# can leave the SRTL input coordinate mapping behind the rendered display.
def tab(index):
    labels={0:['Next Alarm','다음알람'],2:['Calendar','달력'],4:['Settings','설정']}
    code="""(() {
      BottomNavigationBar? bar;
      void visit(Element e){if(e.widget is BottomNavigationBar)bar=e.widget as BottomNavigationBar;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      final i=bar!.items.indexWhere((item)=>LABELS.contains(item.label));
      if(i<0)throw StateError('Missing navigation label');bar!.onTap!(i);return 'layout navigation callback';
    })()""".replace('LABELS',json.dumps(labels[index],ensure_ascii=False))
    ev('general_nav_'+str(index),'main.dart',code);time.sleep(.7)

for lang in ['en-US','ko-KR']:
    locale(lang);tab(2);seed(lang,'individual')
    ev('general_populated_alarms_'+lang,'screens/calendar_tab.dart',"""(() async {
      _CalendarTabState? s;void visit(Element e){if(e is StatefulElement && e.state is _CalendarTabState)s=e.state as _CalendarTabState;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      final service=DatabaseService.instance;final schedule=(await service.getShiftSchedule())!;
      await service.replaceAllAlarmTemplates([for(final shift in (schedule.activeShiftTypes ?? schedule.shiftTypes))for(var i=0;i<3;i++)
        {'shift_type':shift,'time':'23:${55+i}','alarm_type_id':3,'day_offset':0}]);
      await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
      final d=await service.database;
      await d.delete('alarm_history',where:'alarm_id>=?',whereArgs:[990000]);
      for(var i=0;i<24;i++){
        final at=DateTime(2026,10,2,7,11).subtract(Duration(days:i));
        await d.insert('alarm_history',{'alarm_id':990000+i,'scheduled_time':'07:11','scheduled_date':at.toIso8601String(),
          'actual_ring_time':at.toIso8601String(),'dismiss_type':i%2==0?'dismissed':'timeout','snooze_count':i%3,
          'shift_type':schedule.shiftTypes[i%schedule.shiftTypes.length],'created_at':at.toIso8601String(),'day_offset':0});
      }
      await s!.ref.read(alarmNotifierProvider.notifier).refresh();return 'future silent alarms after 23:55 and 24 past records';
    })()""")
    for opened in [False,True]:
        if not any(scales_for(lang,opened,s) for s in ['next_alarm']+[r[0] for r in routes]+[d[0] for d in dialogs]):continue
        check_time();fold(opened)
        adb('shell','settings','put','system','font_scale','1.0');time.sleep(.5)
        if scales_for(lang,opened,'next_alarm'):
            tab(0);measure(lang,opened,'next_alarm')
        for scene,library,widget in routes:
            check_time()
            if not scales_for(lang,opened,scene):continue
            push('screens/'+library+'.dart',widget+'()')
            measure(lang,opened,scene);back()
        tab(4)
        for scene,method in dialogs:
            check_time()
            if not scales_for(lang,opened,scene):continue
            invoke('screens/settings_tab.dart','_SettingsTabState',method)
            measure(lang,opened,scene);back()
os.environ.pop('SRTL_INSPECT_SCALES',None)
adb('shell','settings','put','system','font_scale','1.0')
print('GENERAL ENDPOINT EXECUTION COMPLETE; visual review recorded separately.',flush=True)
