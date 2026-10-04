"""Comparable v2 calendar originals; synthetic data on explicitly selected SRTL."""
import hashlib
import json
import os
import shutil
import time
from pathlib import Path
from usb_audit_device import SERIAL, OUT, ROOT, adb, connect_vm
from srtl_current_audit import ev, locale, fold, tab, push, back, inspect

assert SERIAL.startswith('localhost:')
DEVICE = os.environ.get('SRTL_DEVICE_NAME', 'Fold8Ultra')
CAPTURE_ROOT = ROOT/os.environ.get('SRTL_CAPTURE_ROOT','artifacts/srtl_2026-10-03')
DEST = CAPTURE_ROOT/DEVICE/os.environ.get('SRTL_CAPTURE_SET','numbered_v2')
DEST.mkdir(parents=True, exist_ok=True)
CAT = json.loads((ROOT/'artifacts/srtl_2026-10-03/capture_catalog.json').read_text(encoding='utf8'))
SELECTED_NUMBERS = {n.strip().zfill(3) for n in os.environ.get('SRTL_CAPTURE_NUMBERS','').split(',') if n.strip()}
APK = ROOT/'build/app/outputs/flutter-apk/app-dev-debug.apk'
manifest = {'device': DEVICE, 'serial': SERIAL, 'captures': []}
old_manifest = DEST/'manifest.json'
if old_manifest.exists(): manifest=json.loads(old_manifest.read_text(encoding='utf8'))

def seed(lang, roster=None):
    ko=lang=='ko-KR'
    names=['주간','야간집중근무','휴무','오전지원근무','연차'] if ko else ['Day','Late Night Shift','Off','Morning Support','Leave']
    # The actual roster editor accepts one-character team names only.
    teams=['가','나','다','라','마'] if ko else ['A','B','C','D','E']
    pattern=[names[i] for i in [0,0,2,2,1,1,2,2]]
    def cycle(p,i):return {'kind':'cycle','shifts':p,'anchor':'2026-10-03','index':i}
    rules=[cycle(pattern,i) for i in [0,2,4,6]]
    if roster=='individual':
        rules[1]=cycle([names[0],names[2],names[1]],0)
        rules[3]=cycle([names[0]]*3+[names[2]]*3+[names[1]]*3+[names[2]]*3,0)
        rules.append({'kind':'weekly','shifts':[names[3]]*5+[names[2]]*2,'anchor':'2024-01-01','index':0})
    config={'version':2,'individual':roster=='individual','myTeamId':'team-2',
            'teams':[{'id':f'team-{i}','name':teams[i],'rule':r} for i,r in enumerate(rules)]}
    config_code='null' if not roster else 'TeamScheduleConfig.fromJson(jsonDecode('+json.dumps(json.dumps(config,ensure_ascii=False),ensure_ascii=False)+'))'
    exceptions={} if roster else {'2026-10-07':names[3],'2026-10-16':names[4],'2026-10-22':names[3]}
    ev('numbered_fixture_'+lang,'services/database_service.dart',"""(() async {
      final service=DatabaseService.instance;
      final names=NAMES;
      await service.saveTeamScheduleConfig(null);
      await service.saveShiftSchedule(ShiftSchedule(id:1,isRegular:true,pattern:PATTERN,
        todayIndex:4,startDate:DateTime(2026,10,3),shiftTypes:names,activeShiftTypes:names.take(3).toList(),
        assignedDates:EXCEPTIONS,shiftColors:{names[0]:0xff90caf9,names[1]:0xffce93d8,names[2]:0xffc8e6c9,names[3]:0xff80cbc4,names[4]:0xffb0bec5}));
      await service.saveTeamScheduleConfig(CONFIG);
      await service.replaceAllAlarmTemplates([]);
      await kAlarmChannel.invokeMethod('forceNativeRefreshAndWait');
      final db=await service.database;await db.delete('date_memos');
      return 'v2 synthetic fixture';
    })()""".replace('NAMES',json.dumps(names,ensure_ascii=False)).replace('CONFIG',config_code)
        .replace('PATTERN',json.dumps(pattern,ensure_ascii=False)).replace('EXCEPTIONS',json.dumps(exceptions,ensure_ascii=False)))
    memos=['병원 진료 예약','가족과 저녁 모임','신규 장비 안전교육 참석'] if ko else ['Clinic appointment','Dinner with family','New equipment safety training']
    ev('numbered_memos_'+lang,'screens/calendar_tab.dart',"""(() async {
      _CalendarTabState? s;void visit(Element e){if(e is StatefulElement && e.state is _CalendarTabState)s=e.state as _CalendarTabState;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      await s!.ref.read(scheduleProvider.notifier).refresh();
      final memos=MEMOS;
      for(final day in [2,3,4,12,18,25])for(var i=0;i<(day%3)+1;i++){
        await s!.ref.read(memoProvider.notifier).createMemo('2026-10-${day.toString().padLeft(2,"0")}',memos[i]);
      }return 'localized multiple memos';
    })()""".replace('MEMOS',json.dumps(memos,ensure_ascii=False)))
    return {'names':names,'pattern':pattern,'exceptions':exceptions,'memos':memos,'roster':config if roster else None}

def save(row, fixture, status='captured'):
    entry=dict(row,status=status)
    entry['font_scale']=os.environ.get('SRTL_SCALE','1.0')
    if status=='captured':
        stem='numbered_'+row['number'];inspect(stem)
        target=DEST/row['filename'];shutil.copy2(OUT/(stem+'.png'),target)
        from PIL import Image
        entry.update(sha256=hashlib.sha256(target.read_bytes()).hexdigest(),pixels=list(Image.open(target).size),
                     fixture_data=fixture,apk_sha256=hashlib.sha256(APK.read_bytes()).hexdigest())
    manifest['captures']=[e for e in manifest['captures'] if e['number']!=row['number']]+[entry]
    old_manifest.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')

def save_scales(row, fixture, status='captured'):
    global DEST, manifest, old_manifest
    scales=os.environ.get('SRTL_CAPTURE_SCALES')
    if not scales:
        save(row,fixture,status);return
    for scale in scales.split(','):
        os.environ['SRTL_SCALE']=scale
        prefix=os.environ.get('SRTL_CAPTURE_SCALE_PREFIX')
        DEST=CAPTURE_ROOT/DEVICE/((prefix+scale) if prefix else ('numbered_v3' if scale=='1.0' else 'scale_'+scale))
        DEST.mkdir(parents=True,exist_ok=True);old_manifest=DEST/'manifest.json'
        manifest=json.loads(old_manifest.read_text(encoding='utf-8')) if old_manifest.exists() else {'device':DEVICE,'serial':SERIAL,'captures':[]}
        if status=='captured':
            adb('shell','settings','put','system','font_scale',scale);time.sleep(.6)
        save(row,fixture,status)

def run():
    connect_vm()
    adb('shell','settings','put','system','font_scale',os.environ.get('SRTL_SCALE','1.0'));time.sleep(2)
    for lang in os.environ.get('SRTL_LANGS','ko-KR,en-US').split(','):
        locale(lang);tab(2)
        for mode in os.environ.get('SRTL_MODES','main,common,individual').split(','):
            fixture=seed(lang,None if mode=='main' else mode)
            for opened in [False,True]:
                if os.environ.get('SRTL_POSTURE') and os.environ['SRTL_POSTURE']!=('open' if opened else 'closed'):continue
                fold(opened)
                rows=[r for r in CAT['captures'] if r['language']==lang and r['posture']==('open' if opened else 'closed')
                      and ((mode=='main' and r['screen']=='main') or (r['screen']=='roster' and r['variant']==mode))]
                for row in rows:
                    if SELECTED_NUMBERS and row['number'] not in SELECTED_NUMBERS:continue
                    if mode=='main':
                        if lang=='en-US' and row['variant'] in ['initialBadge','underline','eventChip','editorial']:
                            save_scales(row,fixture,'not_available_in_app');continue
                        ev('numbered_theme','screens/calendar_tab.dart',"""(() async {
                          _CalendarTabState? s;void visit(Element e){if(e is StatefulElement && e.state is _CalendarTabState)s=e.state as _CalendarTabState;e.visitChildren(visit);}
                          WidgetsBinding.instance.rootElement!.visitChildren(visit);
                          await s!.ref.read(calendarThemeProvider.notifier).setTheme(CalendarThemeId.THEME);return 'selected';
                        })()""".replace('THEME',row['variant']))
                        save_scales(row,fixture)
                    else:
                        push('screens/all_shifts_view.dart','AllShiftsView()');save_scales(row,fixture);back()
    print('Numbered native originals completed; visual review still required.')

if __name__=='__main__':
    run()
