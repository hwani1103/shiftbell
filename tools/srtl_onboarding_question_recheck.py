"""Device proof for semantic Korean line break after the one-line l10n change."""
from usb_audit_device import connect_vm, adb
from srtl_current_audit import locale, fold, push, back, ev, inspect
from srtl_extra_layouts import bottom

connect_vm();locale('ko-KR')
for opened in [False, True]:
    fold(opened)
    push('screens/onboarding_screen.dart','OnboardingScreen()')
    ev('onboarding_question_draft','screens/onboarding_screen.dart',"""(() {
      _OnboardingScreenState? s;void visit(Element e){if(e is StatefulElement && e.state is _OnboardingScreenState)s=e.state as _OnboardingScreenState;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);
      if(!s!.context.l10n.onboardingTodayShiftQuestion('10월 3일').contains('\\n'))throw StateError('New line break not loaded');
      s!.setState((){s!._pattern=List.generate(40,(i)=>s!._baseShiftTypes[i%s!._baseShiftTypes.length]);s!._todayIndex=39;s!._step=2;});return '40 slots and semantic two-line question';
    })()""")
    name='ko-KR_'+('open' if opened else 'closed')+'_onboarding_question_fixed'
    inspect(name);bottom(name)
    ev('onboarding_question_exit','screens/onboarding_screen.dart',"""(() {
      _OnboardingScreenState? s;void visit(Element e){if(e is StatefulElement && e.state is _OnboardingScreenState)s=e.state as _OnboardingScreenState;e.visitChildren(visit);}
      WidgetsBinding.instance.rootElement!.visitChildren(visit);s!.setState((){s!._step=0;});return 'exit';
    })()""")
    back()
adb('shell','settings','put','system','font_scale','1.0')
