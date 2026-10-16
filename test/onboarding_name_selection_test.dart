import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/theme/app_ui_theme.dart';
import 'package:shiftbell/widgets/app_ui_components.dart';
import 'onboarding_pattern_feedback_test.dart' show pumpOnboarding;

final names = find.byKey(const ValueKey('onboarding-shift-names'));
final choices = find.byKey(const ValueKey('onboarding-shift-choices'));
final preview = find.byKey(const ValueKey('onboarding-pattern-preview'));

void main() {
  testWidgets('name selection copy, deletion, empty guard and add recovery',
      (tester) async {
    final l = await pumpOnboarding(
        tester, const Locale('ko'), const Size(400, 800), 1, GlobalKey());
    expect(find.text('사용되는 근무명을 선택해주세요.'), findsOneWidget);
    expect(find.text('사용하지 않는 근무명은 탭하면 지워져요.'), findsOneWidget);
    expect(find.text(l.onboardingShiftNamesReadyHint), findsOneWidget);
    expect(find.text(l.onboardingShortNamesHint), findsNothing);
    for (final name in [
      l.shiftDay,
      l.shiftNight,
      l.shiftMorning,
      l.shiftAfternoon,
      l.shiftDayOff,
      l.shiftAnnualLeave
    ]) {
      await tester.tap(find.descendant(of: names, matching: find.text(name)));
      await tester.pumpAndSettle();
      expect(
          find.descendant(of: names, matching: find.text(name)), findsNothing);
    }
    AppUiButton next() => tester.widget<AppUiButton>(
        find.widgetWithText(AppUiButton, l.onboardingNextPattern));
    expect(next().onPressed, isNull);
    await tester.tap(find.text(l.onboardingAddShiftName));
    await tester.pumpAndSettle();
    expect(find.text(l.onboardingShortNamesHint), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'A');
    await tester.tap(find.text(l.commonAdd));
    await tester.pumpAndSettle();
    expect(next().onPressed, isNotNull);
    await tester.tap(find.descendant(of: names, matching: find.text('A')));
    await tester.pumpAndSettle();
    expect(next().onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'removing a used name on back clears its slots and today selection',
      (tester) async {
    final l = await pumpOnboarding(
        tester, const Locale('ko'), const Size(400, 800), 1, GlobalKey());
    await tester.tap(find.text(l.onboardingNextPattern));
    await tester.pumpAndSettle();
    expect(find.text(l.onboardingSelectedShiftNames), findsOneWidget);
    expect(find.text(l.onboardingProvidedShiftNames), findsNothing);
    for (final name in [l.shiftDay, l.shiftNight]) {
      await tester.tap(find.descendant(of: choices, matching: find.text(name)));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(l.onboardingCompletePattern));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding-pattern-slot-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester
        .tap(find.descendant(of: names, matching: find.text(l.shiftNight)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.onboardingNextPattern));
    await tester.pumpAndSettle();
    expect(find.descendant(of: choices, matching: find.text(l.shiftNight)),
        findsNothing);
    expect(find.descendant(of: preview, matching: find.text(l.shiftNight)),
        findsNothing);
    expect(find.descendant(of: preview, matching: find.text(l.shiftDay)),
        findsOneWidget);
    expect(
        tester
            .widget<AppUiButton>(
                find.widgetWithText(AppUiButton, l.onboardingNextAlarms))
            .onPressed,
        isNull);
    expect(find.text(l.onboardingTodayPositionHint), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'today guide keeps pulsing until an actual pattern slot is selected',
      (tester) async {
    final l = await pumpOnboarding(
        tester, const Locale('ko'), const Size(400, 800), 1, GlobalKey(),
        reduceMotion: false);
    await tester.tap(find.text(l.onboardingNextPattern));
    await tester.pumpAndSettle();
    for (final name in [l.shiftDay, l.shiftNight]) {
      await tester.tap(find.descendant(of: choices, matching: find.text(name)));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(l.onboardingCompletePattern));
    await tester.pump();
    await tester.pump(AppUiMotion.transition);
    final guide = find.byKey(const ValueKey('onboarding-today-guide'));
    final attention =
        find.ancestor(of: guide, matching: find.byType(AppUiAttention)).first;
    final before = tester.getRect(attention);
    await tester.pump(AppUiMotion.attentionCycle * 6);
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(tester.getRect(attention), before);
    expect(
        tester
            .widget<AppUiButton>(
                find.widgetWithText(AppUiButton, l.onboardingNextAlarms))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('onboarding-pattern-slot-1')));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(
        tester
            .widget<AppUiButton>(
                find.widgetWithText(AppUiButton, l.onboardingNextAlarms))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    testWidgets(
        'attention cue stays gentle and repeats until disabled, reduced=$reduced',
        (tester) async {
      const key = ValueKey('cue');
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: const Scaffold(
                  body: Center(
                      child: AppUiAttention(
                          child: AppUiText('오늘 근무를 선택해주세요.',
                              key: key,
                              role: AppTextRole.section,
                              tone: AppTextTone.selection)))))));
      final before = tester.getRect(find.byKey(key));
      final fade = find
          .ancestor(of: find.byKey(key), matching: find.byType(FadeTransition))
          .first;
      await tester.pump(AppUiMotion.attentionCycle ~/ 2);
      expect(tester.getSize(find.byKey(key)), before.size);
      expect(tester.widget<FadeTransition>(fade).opacity.value,
          reduced ? 1 : closeTo(AppUiMotion.attentionLowOpacity, .01));
      final scale = find
          .ancestor(of: find.byKey(key), matching: find.byType(ScaleTransition))
          .first;
      expect(tester.widget<ScaleTransition>(scale).scale.value,
          reduced ? 1 : closeTo(AppUiMotion.attentionLowScale, .001));
      await tester.pump(AppUiMotion.attentionCycle * 5);
      expect(tester.widget<FadeTransition>(fade).opacity.value,
          reduced ? 1 : closeTo(AppUiMotion.attentionLowOpacity, .01));
      expect(tester.getSize(find.byKey(key)), before.size);
      expect(tester.binding.hasScheduledFrame, !reduced);
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: const Scaffold(
                  body: Center(
                      child: AppUiAttention(
                          enabled: false,
                          child: AppUiText('오늘 근무를 선택해주세요.',
                              key: key,
                              role: AppTextRole.section,
                              tone: AppTextTone.selection)))))));
      await tester.pumpAndSettle();
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.widget<ScaleTransition>(scale).scale.value, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
