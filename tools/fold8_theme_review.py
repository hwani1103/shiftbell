"""October theme comparison on an explicitly selected SRTL dev device."""
import hashlib
import json
import os
import time
from pathlib import Path

# Never fall through to the personal USB device default in the shared helpers.
assert os.environ.get('SHIFTBELL_AUDIT_SERIAL', '').startswith('localhost:')
assert os.environ.get('SHIFTBELL_AUDIT_DDS_URL')
from usb_audit_device import adb, connect_vm, capture, OUT, ROOT, PACKAGE, SERIAL
from srtl_current_audit import ev

PLAN = json.loads((ROOT / 'artifacts/fold8_theme_review_2026_10_08/capture_plan.json').read_text(encoding='utf-8'))
FIND = '''_CalendarTabState? s;
void visit(Element e){if(e is StatefulElement && e.state is _CalendarTabState)s=e.state as _CalendarTabState;e.visitChildren(visit);}
WidgetsBinding.instance.rootElement!.visitChildren(visit);
if(s==null)throw StateError('Calendar state missing');'''


def seed(tag):
    data = PLAN['locales'][tag]
    ev('seed_' + tag, 'services/database_service.dart', '''(() async {
      final service=DatabaseService.instance;
      final names=NAMES;
      await service.saveTeamScheduleConfig(null);
      await service.saveShiftSchedule(ShiftSchedule(id:1,isRegular:true,
        pattern:PATTERN,todayIndex:0,startDate:DateTime(2026,10,1),
        shiftTypes:names,activeShiftTypes:names,
        shiftColors:{names[0]:0xff1976d2,names[1]:0xff7e57c2,names[2]:0xff26a69a,names[3]:0xffef5350}));
      final db=await service.database;
      await db.delete('date_memos',where:'date >= ? AND date < ?',whereArgs:['2026-10-01','2026-11-01']);
      final memos=MEMOS;
      final counts=COUNTS;
      for(final item in counts.entries)for(var i=0;i<item.value;i++) {
        final id=await service.createMemo(item.key,memos[i]);
        if(id==null)throw StateError('Memo fixture rejected');
      }
      return 'October schedule and 12 memos saved; no alarm templates created';
    })()'''.replace('NAMES', json.dumps(data['names'], ensure_ascii=False))
       .replace('PATTERN', json.dumps(data['pattern'], ensure_ascii=False))
       .replace('MEMOS', json.dumps(data['memos'], ensure_ascii=False))
       .replace('COUNTS', json.dumps(PLAN['memo_counts'])))
    ev('main_' + tag, 'main.dart', '''(() async {
      final p=await SharedPreferences.getInstance();
      for(final key in ['permissions_requested','welcome_popup_shown','shift_assign_tutorial_shown','condition_tab_tutorial_shown','schedule_tab_tutorial_shown','one_touch_alarm_tutorial_shown'])await p.setBool(key,true);
      NavigatorState? nav;
      void visit(Element e){if(e is StatefulElement && e.state is NavigatorState)nav=e.state as NavigatorState;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      await ProviderScope.containerOf(nav!.context,listen:false).read(scheduleProvider.notifier).refresh();
      nav!.pushAndRemoveUntil(MaterialPageRoute(builder:(_)=>const MainScreen(initialIndex:2)),(_)=>false);
      return 'normal MainScreen calendar';
    })()''')
    time.sleep(1)
    ev('month_' + tag, 'screens/calendar_tab.dart', '(() async {' + FIND + '''
      await s!.ref.read(scheduleProvider.notifier).refresh();
      s!.ref.read(memoProvider.notifier).clear();
      await s!.ref.read(memoProvider.notifier).loadMemosForDateRange(DateTime(2026,10,1),DateTime(2026,11,1));
      s!.setState((){s!._focusedDay=DateTime(2026,10,9);});
      final counts=s!.ref.read(memoProvider).map((key,value)=>MapEntry(key,value.length));
      if(counts['2026-10-09']!=3)throw StateError('Missing October 9 memos');
      return counts.toString();
    })()''')


def run():
    connect_vm()
    backup = OUT / 'before_fixture.tar'
    if not backup.exists():
        backup.write_bytes(adb('exec-out', 'run-as', PACKAGE, 'tar', '-cf', '-', '/data/user_de/0/' + PACKAGE + '/databases', 'shared_prefs'))
    manifest = json.loads((OUT / 'manifest.json').read_text(encoding='utf-8')) if (OUT / 'manifest.json').exists() else {'serial': SERIAL, 'source': 'native SRTL screenshots', 'captures': []}
    for tag in [os.environ['REVIEW_LOCALE']]:
        adb('shell', 'cmd', 'locale', 'set-app-locales', PACKAGE, '--locales', tag)
        time.sleep(2)
        connect_vm()
        seed(tag)
        if os.environ.get('REVIEW_SEED_ONLY') == '1':
            ev('restore_theme', 'screens/calendar_tab.dart', '(() async {' + FIND + '''
              await s!.ref.read(calendarThemeProvider.notifier).setTheme(CalendarThemeId.mainWhite);
              return 'Korean calendar restored';
            })()''')
            return
        selected_themes = os.environ.get('REVIEW_THEMES', '').split(',') if os.environ.get('REVIEW_THEMES') else PLAN['locales'][tag]['themes']
        manifest['captures'] = [r for r in manifest['captures'] if r['locale'] != tag or r['theme'] not in selected_themes or (os.environ.get('REVIEW_POSTURE') and r['posture'] != os.environ['REVIEW_POSTURE'])]
        for posture, state in [('closed', '0'), ('open', '3')]:
            if os.environ.get('REVIEW_POSTURE') and posture != os.environ['REVIEW_POSTURE']:
                continue
            adb('shell', 'cmd', 'device_state', 'state', state)
            time.sleep(2)
            adb('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
            adb('shell', 'wm', 'dismiss-keyguard')
            adb('shell', 'am', 'start', '-n', PACKAGE + '/com.hwani1103.shiftbell.MainActivity')
            time.sleep(2)
            for theme in selected_themes:
                stem = f'{tag}_{theme}_{posture}'
                ev(stem + '_theme', 'screens/calendar_tab.dart', '(() async {' + FIND + '''
                  await s!.ref.read(calendarThemeProvider.notifier).setTheme(CalendarThemeId.THEME);
                  s!.setState((){s!._focusedDay=DateTime(2026,10,9);});
                  return 'selected THEME';
                })()'''.replace('THEME', theme))
                time.sleep(.5)
                geometry = ev(stem + '_window', 'screens/calendar_tab.dart', '(() {' + FIND + '''
                  if(ModalRoute.of(s!.context)?.isCurrent!=true)throw StateError('Calendar is obscured by another route');
                  final size=MediaQuery.sizeOf(s!.context);
                  final v=View.of(s!.context);
                  var cell='unknown';
                  void table(Element e){if(e.widget is TableCalendar){final w=e.widget as TableCalendar;final r=e.findRenderObject();if(r is RenderBox)cell='${r.size.width/7}x${w.rowHeight}';}e.visitChildren(table);}
                  s!.context.visitChildElements(table);
                  return 'cell=$cell|${Localizations.localeOf(s!.context)}|${size.width}x${size.height}|dpr=${v.devicePixelRatio}|split=${WideCalendarCell.appliesTo(size)}';
                })()''')
                if '|' + tag.split('-')[0] not in geometry:
                    raise RuntimeError('Capture locale mismatch: ' + geometry)
                focus=adb('shell', 'dumpsys', 'window').decode('utf-8',errors='replace')
                if not any(PACKAGE in line and 'mCurrentFocus' in line for line in focus.splitlines()):
                    raise RuntimeError('Dev app is not foreground')
                capture(stem)
                p = OUT / (stem + '.png')
                manifest['captures'].append({'locale': tag, 'theme': theme, 'posture': posture,
                    'file': p.name, 'window': geometry, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()})
                (OUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
                print('CAPTURE', len(manifest['captures']), '/34', stem, flush=True)


if __name__ == '__main__':
    run()
