"""Targeted recheck after permission banner stops overlaying tab content."""
import os, time, json
from usb_audit_device import connect_vm, adb, OUT, PACKAGE
from srtl_current_audit import ev, locale, fold, inspect, invoke, back

connect_vm()
os.environ.pop('SRTL_INSPECT_SCALES',None)
def navigate(index):
    ev('permission_nav','main.dart',"""(() {
      BottomNavigationBar? bar;void visit(Element e){if(e.widget is BottomNavigationBar)bar=e.widget as BottomNavigationBar;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);bar!.onTap!(INDEX);return 'navigation callback';
    })()""".replace('INDEX',str(index)))
    time.sleep(.8)

def refresh_banner():
    ev('permission_banner_refresh','widgets/permission_warning_banner.dart',"""(() async {
      _PermissionWarningBannerState? s;void visit(Element e){if(e is StatefulElement && e.state is _PermissionWarningBannerState)s=e.state as _PermissionWarningBannerState;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);await s!._checkPermissions();return 'banner refreshed';
    })()""")
    time.sleep(.8)

rows=[]
for allowed in ([] if os.environ.get('SRTL_WORDWRAP_ONLY')=='1' else [False,True]):
    adb('shell','appops','set',PACKAGE,'SYSTEM_ALERT_WINDOW','allow' if allowed else 'deny')
    refresh_banner()
    for lang in ['en-US','ko-KR']:
        locale(lang)
        for opened in ([False,True] if not allowed else [False]):
            fold(opened)
            for scale in (['1.0','1.3'] if not allowed else ['1.3']):
                adb('shell','settings','put','system','font_scale',scale);time.sleep(.8)
                for tab_index,scene in [(0,'next_alarm'),(1 if lang=='en-US' else 2,'calendar')]:
                    navigate(tab_index)
                    name=f'permission_{"granted" if allowed else "missing"}_{lang}_{"open" if opened else "closed"}_{scene}_{scale}'
                    inspect(name)
                    if scene=='next_alarm':
                        result=ev(name+'_bounds','main.dart',"""(() {
                          RenderBox? action;RenderBox? banner;BottomNavigationBar? nav;RenderBox? navBox;
                          void visit(Element e){
                            if(e.widget is Offstage && (e.widget as Offstage).offstage)return;
                            if(e.widget is Text && ['Turn Off This Alarm','이 알람 끄기'].contains((e.widget as Text).data))action=e.findRenderObject() as RenderBox?;
                            if(e.widget is PermissionWarningBanner)banner=e.findRenderObject() as RenderBox?;
                            if(e.widget is BottomNavigationBar)navBox=e.findRenderObject() as RenderBox?;
                            e.visitChildren(visit);
                          }WidgetsBinding.instance.rootElement!.visitChildren(visit);
                          if(action==null || banner==null || navBox==null)throw StateError('Missing action/banner/navigation');
                          final end=action!.localToGlobal(Offset(0,action!.size.height)).dy;
                          final limit=banner!.size.height>0 ? banner!.localToGlobal(Offset.zero).dy : navBox!.localToGlobal(Offset.zero).dy;
                          if(end>limit)throw StateError('Dismiss action obscured: $end > $limit');
                          return 'dismissBottom=$end contentLimit=$limit bannerHeight=${banner!.size.height}';
                        })()""")
                    else:result='calendar pixels captured for visual review'
                    rows.append({'name':name,'result':result})
                    (OUT/'permission_recheck.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf8')
locale('ko-KR')
for opened in [False,True]:
    fold(opened);navigate(4)
    invoke('screens/settings_tab.dart','_SettingsTabState','_showChangeScheduleDialog()')
    for scale in ['1.0','1.3']:
        adb('shell','settings','put','system','font_scale',scale);time.sleep(.8)
        inspect(f'ko_schedule_wordwrap_{"open" if opened else "closed"}_{scale}')
    back()
adb('shell','settings','put','system','font_scale','1.0')
print('Permission layout recheck completed; overlay permission left granted.',flush=True)
