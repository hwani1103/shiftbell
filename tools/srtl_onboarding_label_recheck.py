"""Recheck onboarding shift titles after the narrow-card label correction."""
import time
from usb_audit_device import adb,connect_vm
from srtl_current_audit import locale,fold,push,back,ev,inspect
connect_vm()
for lang in ['en-US','ko-KR']:
 locale(lang)
 for opened in [False,True]:
  fold(opened)
  push('screens/onboarding_screen.dart','OnboardingScreen()')
  ev('onboarding_card_draft','screens/onboarding_screen.dart',"""(() {
   _OnboardingScreenState? s;void visit(Element e){if(e is StatefulElement && e.state is _OnboardingScreenState)s=e.state as _OnboardingScreenState;e.visitChildren(visit);}
   WidgetsBinding.instance.rootElement!.visitChildren(visit);
   s!.setState((){s!._pattern=List.generate(40,(i)=>s!._baseShiftTypes[i%s!._baseShiftTypes.length]);s!._todayIndex=39;s!._step=3;});return 'draft final cards';
  })()""")
  inspect(lang+('_open_' if opened else '_closed_')+'onboarding_label_fixed')
  ev('onboarding_exit','screens/onboarding_screen.dart',"""(() {
   _OnboardingScreenState? s;void visit(Element e){if(e is StatefulElement && e.state is _OnboardingScreenState)s=e.state as _OnboardingScreenState;e.visitChildren(visit);}
   WidgetsBinding.instance.rootElement!.visitChildren(visit);s!.setState((){s!._step=0;});return 'exit';
  })()""")
  back()
adb('shell','settings','put','system','font_scale','1.0')
