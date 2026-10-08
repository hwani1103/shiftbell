import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/constants/layout_limits.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/team_rule.dart';
import 'package:shiftbell/models/team_schedule_config.dart';
import 'package:shiftbell/screens/team_rule_editor_screen.dart';
import 'package:shiftbell/screens/team_schedule_edit_screen.dart';
import 'package:shiftbell/widgets/app_button.dart';
import 'package:shiftbell/widgets/team_rule_card.dart';

void main() {
  final date = DateTime(2026,10,3);
  const shifts = ['Day Shift','Night Shift','Day Off','Office Work'];
  Future<void> mount(WidgetTester tester, Widget child, Size size, Locale locale, double scale) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = size; tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: ScreenUtilInit(designSize: const Size(360,780),
      builder: (context,_) {
        ScreenUtil.configure(data:appContentMediaQuery(MediaQueryData.fromView(View.of(context))), designSize:const Size(360,780));
        return MaterialApp(locale:locale, supportedLocales:AppLocalizations.supportedLocales,
          localizationsDelegates:AppLocalizations.localizationsDelegates,
          builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)),child:child!),
          home:child);
      })));
    await tester.pumpAndSettle();
  }
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final scrollable = find.byType(Scrollable).first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 100, scrollable:scrollable, maxScrolls:150);
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(finder), alignment:0.5);
    await tester.pumpAndSettle();
  }
  for (final size in [const Size(320,568),const Size(360,320),const Size(412,915),
    const Size(600,720),const Size(806,895),const Size(1000,750)]) {
    for (final lang in ['ko','en']) {
      for (final scale in [1.0,2.0]) {
        testWidgets('weekly assignment $size $lang text=$scale', (tester) async {
          await mount(tester, TeamRuleEditorScreen(team:'E',basePattern:shifts,
            shiftTypes:shifts,date:date),size,Locale(lang),scale);
          final mode = find.byKey(const ValueKey('rule-mode-2'));
          await reveal(tester, mode); await tester.tap(mode); await tester.pumpAndSettle();
          expect(tester.widget<AppButton>(find.byKey(const ValueKey('rule-save'))).onPressed,isNull);
          final pick = find.byKey(const ValueKey('rule-shift-Office Work'));
          await reveal(tester, pick); await tester.tap(pick); await tester.pumpAndSettle();
          for(var i=0;i<7;i++) {
            final day=find.byKey(ValueKey('rule-weekday-$i'));
            await reveal(tester, day); await tester.tap(day); await tester.pumpAndSettle();
          }
          expect(tester.widget<AppButton>(find.byKey(const ValueKey('rule-save'))).onPressed,isNotNull);
          expect(tester.takeException(),isNull);
        });
      }
    }
  }

  testWidgets('40-day cycle remains scrollable and editing clears stale reference index', (tester) async {
    await mount(tester, TeamRuleEditorScreen(team:'B',basePattern:shifts,shiftTypes:shifts,date:date,
      initial:TeamRule.cycle(List.generate(40,(i)=>shifts[i%4]),date,39)),const Size(320,568),const Locale('en'),2);
    expect(tester.widget<AppButton>(find.byKey(const ValueKey('rule-save'))).onPressed,isNotNull);
    final last=find.byKey(const ValueKey('rule-position-39'));
    await reveal(tester, last); await tester.tap(last); await tester.pumpAndSettle();
    final remove=find.byKey(const ValueKey('rule-cycle-remove-3'));
    await reveal(tester, remove); await tester.tap(remove); await tester.pumpAndSettle();
    expect(tester.widget<AppButton>(find.byKey(const ValueKey('rule-save'))).onPressed,isNull);
    expect(find.byKey(const ValueKey('rule-position-39')),findsNothing);
    expect(tester.takeException(),isNull);
  });

  testWidgets('identical current shifts select different teams; current team stays locked', (tester) async {
    final rules={for(final n in ['A','B','C','D','E','F']) n:TeamRule.cycle(shifts,date,0)};
    final config=TeamScheduleConfig(names:rules.keys.toList(),offsets:{},myTeam:'C',individual:true,rules:rules).materialize(shifts);
    await mount(tester,TeamScheduleEditScreen(teams:config,pattern:shifts,date:date),
      const Size(320,568),const Locale('ko'),2);
    await tester.tap(find.byKey(const ValueKey('team-edit-switch'))); await tester.pumpAndSettle();
    for(final n in ['A','E','B','F']) {
      final card=find.byKey(ValueKey('team-switch-$n'));
      await reveal(tester, card); await tester.tap(card); await tester.pumpAndSettle();
      expect(tester.widget<TeamRuleCard>(card).selected,isTrue);
    }
    await reveal(tester, find.byKey(const ValueKey('team-switch-C')));
    expect(tester.widget<TeamRuleCard>(find.byKey(const ValueKey('team-switch-C'))).onTap,isNull);
    expect(tester.takeException(),isNull);
  });
}
