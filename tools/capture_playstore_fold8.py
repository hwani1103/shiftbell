"""Five raw SRTL cover-calendar captures for store artwork."""
import os, json, time, hashlib, shutil
from pathlib import Path
assert os.environ['SHIFTBELL_AUDIT_SERIAL'].startswith('localhost:')
from usb_audit_device import adb, connect_vm, capture, OUT, PACKAGE
from srtl_current_audit import ev
from fold8_theme_review import FIND

SCENES = [
 ('ko-KR','Korean','Korea','minimal','SimpleLine',['주간','야간','오후근무','휴무']),
 ('en-US','English','English','periwinkle','Periwinkle',['D','Night','Afternoon Shift','Off']),
 ('pt-BR','Portuguese_Brazil','Brazil','periwinkle','Periwinkle',['Dia','Noite','Turno da tarde','Folga']),
 ('hi-IN','Hindi','Hindi','periwinkle','Periwinkle',['दिन','रात्रि','दोपहर की पाली','छुट्टी']),
 ('de-DE','German','Germany','periwinkle','Periwinkle',['Tag','Nacht','Spätschicht','Frei']),
]
DEST=Path(os.environ['PLAYSTORE_CAPTURE_DEST'])
DEST.mkdir(parents=True,exist_ok=True)
connect_vm()
backup=OUT/'before_store_scene.tar'
if not backup.exists():
 backup.write_bytes(adb('exec-out','run-as',PACKAGE,'tar','-cf','-','/data/user_de/0/'+PACKAGE+'/databases','shared_prefs'))
adb('shell','cmd','device_state','state','0')
time.sleep(2)
adb('shell','input','keyevent','KEYCODE_WAKEUP')
adb('shell','wm','dismiss-keyguard')
adb('shell','am','start','-n',PACKAGE+'/com.hwani1103.shiftbell.MainActivity')
rows=[]
for tag,folder,country,theme,theme_name,names in SCENES:
 adb('shell','cmd','locale','set-app-locales',PACKAGE,'--locales',tag)
 time.sleep(2)
 connect_vm()
 pattern=[names[i] for i in [0,0,3,3,1,1,3,3,2,2,3,3]]
 ev('store_seed_'+tag,'services/database_service.dart',"""(() async {
 final service=DatabaseService.instance;
 final names=NAMES;
 await service.saveTeamScheduleConfig(null);
 await service.saveShiftSchedule(ShiftSchedule(id:1,isRegular:true,
 pattern:PATTERN,todayIndex:0,startDate:DateTime(2026,10,1),
 shiftTypes:names,activeShiftTypes:names,
 shiftColors:{names[0]:0xff1976d2,names[1]:0xff7e57c2,names[2]:0xff26a69a,names[3]:0xffef5350}));
 final db=await service.database;
 await db.delete('date_memos');
 return 'Same two-day pattern; all calendar memo assignments cleared';
 })()""".replace('NAMES',json.dumps(names,ensure_ascii=False)).replace('PATTERN',json.dumps(pattern,ensure_ascii=False)))
 ev('store_ui_'+tag,'screens/calendar_tab.dart','(() async {'+FIND+"""
 await s!.ref.read(scheduleProvider.notifier).refresh();
 s!.ref.read(memoProvider.notifier).clear();
 await s!.ref.read(memoProvider.notifier).loadMemosForDateRange(DateTime(2026,10,1),DateTime(2026,11,1));
 await s!.ref.read(calendarThemeProvider.notifier).setTheme(CalendarThemeId.THEME);
 s!.setState((){s!._focusedDay=DateTime(2026,10,9);});
 return 'calendar ready';
 })()""".replace('THEME',theme))
 time.sleep(1)
 state=ev('store_verify_'+tag,'screens/calendar_tab.dart','(() {'+FIND+"""
 final size=MediaQuery.sizeOf(s!.context);
 final memoCount=s!.ref.read(memoProvider).values.fold<int>(0,(a,b)=>a+b.length);
 if(memoCount!=0)throw StateError('Memos still visible');
 if(WideCalendarCell.appliesTo(size))throw StateError('Expected cover screen');
 if(ModalRoute.of(s!.context)?.isCurrent!=true)throw StateError('Calendar not foreground route');
 return '${Localizations.localeOf(s!.context)}|${size.width}x${size.height}|memos=$memoCount';
 })()""")
 assert state.split('|')[0].split('_')[0] == tag.split('-')[0],state
 focus=adb('shell','dumpsys','window').decode('utf-8',errors='replace')
 assert any(PACKAGE in line and 'mCurrentFocus' in line for line in focus.splitlines())
 stem=f'{country}_Fold8_Folded_Calendar_{theme_name}'
 capture(stem)
 dest=DEST/(folder+'_'+tag)
 dest.mkdir(parents=True,exist_ok=True)
 target=dest/(stem+'.png')
 shutil.copy2(OUT/(stem+'.png'),target)
 rows.append(dict(locale=tag,file=str(target),state=state,names=names,pattern=pattern,sha256=hashlib.sha256(target.read_bytes()).hexdigest()))
 (OUT/'manifest.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
 print('SAVED',target,flush=True)
# Leave the SRTL dev calendar in Korean, still without memos.
adb('shell','cmd','locale','set-app-locales',PACKAGE,'--locales','ko-KR')
time.sleep(2)
connect_vm()
names=SCENES[0][-1]
pattern=[names[i] for i in [0,0,3,3,1,1,3,3,2,2,3,3]]
ev('store_restore_ko','screens/calendar_tab.dart','(() async {'+FIND+"""
 final names=NAMES;
 await DatabaseService.instance.saveShiftSchedule(ShiftSchedule(id:1,isRegular:true,pattern:PATTERN,
 todayIndex:0,startDate:DateTime(2026,10,1),shiftTypes:names,activeShiftTypes:names,
 shiftColors:{names[0]:0xff1976d2,names[1]:0xff7e57c2,names[2]:0xff26a69a,names[3]:0xffef5350}));
 await s!.ref.read(scheduleProvider.notifier).refresh();
 await s!.ref.read(calendarThemeProvider.notifier).setTheme(CalendarThemeId.minimal);
 return 'Korean Simple Line restored, no memos';
 })()""".replace('NAMES',json.dumps(names,ensure_ascii=False)).replace('PATTERN',json.dumps(pattern,ensure_ascii=False)))
(DEST/'촬영안내.txt').write_text('Fold8 접힘 달력 원본 캡처 5장\n한글: 심플라인 / 영어·브라질 포르투갈어·힌디어·독일어: Periwinkle\n2026년 10월, 2일씩 같은 근무패턴, 메모 없음.\n각 언어 폴더의 이 파일은 스토어 이미지 5종 중 달력용 원본 1종입니다. 나머지 4종은 추후 추가합니다.\n디버그 배너·광고·시스템 UI 포함, 원본 PNG 그대로 저장.\n',encoding='utf-8')
