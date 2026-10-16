import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/theme/app_ui_theme.dart';
import 'package:shiftbell/widgets/app_ui_components.dart';
import 'onboarding_pattern_feedback_test.dart' show pumpOnboarding;

void main() {
  testWidgets(
      'pattern completion separates editing and today selection in a reserved footer',
      (tester) async {
    final l = await pumpOnboarding(
        tester, const Locale('ko'), const Size(400, 800), 2, GlobalKey());
    expect(find.text(l.onboardingStart), findsOneWidget);
    await tester.tap(find.text(l.onboardingNextPattern));
    await tester.pumpAndSettle();
    final provided = find.text(l.onboardingSelectedShiftNames);
    final pattern = find.text(l.onboardingPatternLabel);
    Rect cardFor(Finder text) => tester
        .getRect(find.ancestor(of: text, matching: find.byType(AppUiCard)));
    final providedOffset =
        tester.getRect(provided).topLeft - cardFor(provided).topLeft;
    final patternOffset =
        tester.getRect(pattern).topLeft - cardFor(pattern).topLeft;
    expect(patternOffset, providedOffset);
    final providedStyle = tester.widget<Text>(provided).style;
    final patternStyle = tester.widget<Text>(pattern).style;
    expect(patternStyle?.fontSize, providedStyle?.fontSize);
    expect(patternStyle?.fontWeight, providedStyle?.fontWeight);
    final actionArea =
        find.byKey(const ValueKey('onboarding-pattern-action-area'));
    final footer = tester.getRect(actionArea);
    final cardHeight = cardFor(pattern).height;
    final completion =
        find.byKey(const ValueKey('onboarding-pattern-complete'));
    AppUiButton finish() => tester.widget<AppUiButton>(completion);
    AppUiButton next() => tester.widget<AppUiButton>(find.ancestor(
        of: find.text(l.onboardingNextAlarms),
        matching: find.byType(AppUiButton)));
    expect(finish().onPressed, isNull);
    expect(next().onPressed, isNull);
    expect(find.text(l.onboardingNoPattern), findsNothing);
    expect(find.text(l.onboardingTodayPositionHint), findsNothing);
    expect(find.text('0 / 40'), findsNothing);
    expect(find.text(l.onboardingNextToday), findsNothing);
    final choices = find.byKey(const ValueKey('onboarding-shift-choices'));
    final day = find.descendant(of: choices, matching: find.text(l.shiftDay));
    Future<void> add() async {
      await tester.ensureVisible(day);
      await tester.tap(day);
      await tester.pumpAndSettle();
    }

    await add();
    expect(finish().onPressed, isNull);
    await add();
    expect(finish().onPressed, isNotNull);
    expect(next().onPressed, isNull);
    expect(find.text(l.onboardingTodayPositionHint), findsNothing);
    for (var i = 2; i < 40; i++) await add();
    expect(cardFor(pattern).height, cardHeight);
    expect(tester.getRect(actionArea), footer);
    final preview = find.byKey(const ValueKey('onboarding-pattern-preview'));
    final scrolling = tester.state<ScrollableState>(
        find.descendant(of: preview, matching: find.byType(Scrollable)));
    expect(scrolling.position.maxScrollExtent, greaterThan(0));
    final last = find.byKey(const ValueKey('onboarding-pattern-slot-39'));
    expect(
        tester.getRect(last).bottom, lessThanOrEqualTo(footer.top - 12 + .1));
    await tester.ensureVisible(completion);
    await tester.tap(completion);
    await tester.pumpAndSettle();
    expect(find.text(l.onboardingTodayPositionHint), findsOneWidget);
    expect(find.text(l.onboardingEditPattern), findsOneWidget);
    expect(tester.getRect(actionArea), footer);
    expect(cardFor(pattern).height, cardHeight);
    final sourceChip = find
        .descendant(of: choices, matching: find.byType(AppUiShiftChip))
        .first;
    expect(tester.widget<AppUiShiftChip>(sourceChip).enabled, isFalse);
    final slot = find.byKey(const ValueKey('onboarding-pattern-slot-1'));
    await tester.ensureVisible(slot);
    await tester.tap(slot);
    await tester.pumpAndSettle();
    expect(next().onPressed, isNotNull);
    await tester.tap(slot);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-pattern-slot-39')),
        findsOneWidget);
    expect(tester.widget<AppUiShiftChip>(slot).selected, isTrue);
    await tester.ensureVisible(completion);
    await tester.tap(completion);
    await tester.pumpAndSettle();
    expect(find.text(l.onboardingTodayPositionHint), findsNothing);
    expect(next().onPressed, isNull);
    expect(tester.widget<AppUiShiftChip>(sourceChip).enabled, isFalse,
        reason:
            'forty-entry internal limit remains enforced after switching back');
    await tester.ensureVisible(slot);
    await tester.tap(slot);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('onboarding-pattern-slot-39')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'shared palette recolors onboarding and components without screen overrides',
      (tester) async {
    final blue = AppUiPalette.blue.copyWith(
        background: const Color(0xFFF0F5FC),
        surface: const Color(0xFFFCFDFF),
        primary: const Color(0xFF315FA8),
        onPrimary: const Color(0xFFFFFFFF),
        soft: const Color(0xFFE7EFFB),
        text: const Color(0xFF22334D),
        secondaryText: const Color(0xFF576A84),
        border: const Color(0xFFD4DFEF),
        disabledSurface: const Color(0xFFE2E8F2),
        disabledText: const Color(0xFF68768B));
    final l = await pumpOnboarding(
        tester, const Locale('ko'), const Size(400, 800), 1, GlobalKey(),
        palette: blue);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        blue.background);
    expect(
        tester.widget<Text>(find.text(l.onboardingShiftNameTitle)).style?.color,
        blue.text);
    final next = find.ancestor(
        of: find.text(l.onboardingNextPattern),
        matching: find.byType(FilledButton));
    final button = tester.widget<FilledButton>(next);
    expect(button.style?.backgroundColor?.resolve({}), blue.primary);
    expect(button.style?.backgroundColor?.resolve({WidgetState.disabled}),
        blue.disabledSurface);
    final card = find.byType(AppUiCard).first;
    final container = tester.widget<Container>(
        find.descendant(of: card, matching: find.byType(Container)).first);
    expect((container.decoration as BoxDecoration).color, blue.surface);
    final chip = find.byType(AppUiShiftChip).first;
    final material = tester.widget<Material>(
        find.descendant(of: chip, matching: find.byType(Material)));
    expect(material.color, blue.soft);
    expect(
        tester
            .widget<Text>(
                find.descendant(of: chip, matching: find.byType(Text)))
            .style
            ?.color,
        blue.text);
    await tester.tap(find.text(l.onboardingNextPattern));
    await tester.pumpAndSettle();
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        blue.background);
    expect(
        Theme.of(tester.element(find.byType(AppUiShiftChip).first))
            .extension<AppUiPalette>()
            ?.primary,
        blue.primary);
    expect(tester.takeException(), isNull);
  });
}
