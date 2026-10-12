import os
"""Unobscured KO onboarding drafts after the welcome popup was reviewed."""
import time
from usb_audit_device import connect_vm,adb
from srtl_current_audit import ev,locale,fold,push,back,inspect
from srtl_extra_layouts import bottom
connect_vm();locale('ko-KR')
ev('onboarding_welcome_seen','main.dart',"(() async {final p=await SharedPreferences.getInstance();await p.setBool('welcome_popup_shown',true);return 'welcome separately reviewed';})()")
for opened in [False,True]:
    fold(opened);adb('shell','settings','put','system','font_scale',os.environ.get('SRTL_SCALE','1.3'));time.sleep(1)
    p='ko-KR'+('_open_' if opened else '_closed_')+'extra_'
    push('screens/onboarding_screen.dart','OnboardingScreen()');inspect(p+'onboarding_names')
    for step in [1,2,3,0]:
        ev(p+'onboarding_recheck_'+str(step),'screens/onboarding_screen.dart',"""(() {
          _OnboardingScreenState? s;void visit(Element e){if(e is StatefulElement && e.state is _OnboardingScreenState)s=e.state as _OnboardingScreenState;e.visitChildren(visit);}
          WidgetsBinding.instance.rootElement!.visitChildren(visit);
          s!.setState((){s!._pattern=List.generate(40,(i)=>s!._baseShiftTypes[i%s!._baseShiftTypes.length]);s!._todayIndex=39;s!._step=STEP;});return 'draft only';
        })()""".replace('STEP',str(step)))
        time.sleep(.4)
        if step:inspect(p+'onboarding_'+str(step));bottom(p+'onboarding_'+str(step))
    back()
adb('shell','settings','put','system','font_scale','1.0')
