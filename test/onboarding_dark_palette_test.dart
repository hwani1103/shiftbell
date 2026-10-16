import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/theme/app_ui_theme.dart';
import 'package:shiftbell/widgets/app_ui_components.dart';
import 'package:shiftbell/widgets/alarm_time_editor.dart';
import 'onboarding_pattern_feedback_test.dart' show pumpOnboarding;

void main() {
  testWidgets(
      'dark palette reaches names, today selection, alarm editor and picker',
      (tester) async {
    final dark = AppUiPalette.blue.copyWith(
        background: const Color(0xFF182331),
        surface: const Color(0xFF243347),
        primary: const Color(0xFFA9C7FF),
        onPrimary: const Color(0xFF142744),
        soft: const Color(0xFF30435C),
        text: const Color(0xFFF1F6FF),
        secondaryText: const Color(0xFFB4C5DA),
        border: const Color(0xFF506680),
        danger: const Color(0xFFFFB5BC),
        dangerSurface: const Color(0xFF4B2C36),
        disabledSurface: const Color(0xFF303E51),
        disabledText: const Color(0xFF94A6BD),
        selectionOutline: const Color(0xFFFFC778));
    final l = await pumpOnboarding(
        tester, const Locale('ko'), const Size(400, 800), 1, GlobalKey(),
        palette: dark);
    void expectTheme(Finder finder) {
      final theme = Theme.of(tester.element(finder));
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.onSurface, dark.text);
      expect(theme.colorScheme.onPrimary, dark.onPrimary);
      expect(theme.colorScheme.primaryContainer, dark.soft);
      expect(theme.colorScheme.surfaceContainer, dark.surface);
    }

    expectTheme(find.byType(AppUiCard).first);
    expect(
        tester.widget<Text>(find.text(l.onboardingShiftNameTitle)).style?.color,
        dark.text);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        dark.background);
    await tester.tap(find.text(l.onboardingNextPattern));
    await tester.pumpAndSettle();
    for (final name in [l.shiftDay, l.shiftNight]) {
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('onboarding-shift-choices')),
          matching: find.text(name)));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(l.onboardingCompletePattern));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(find.text(l.onboardingTodayPositionHint))
            .style
            ?.color,
        dark.selectionOutline);
    final slot = find.byKey(const ValueKey('onboarding-pattern-slot-0'));
    final material = find.descendant(of: slot, matching: find.byType(Material));
    expect(
        (tester.widget<Material>(material).shape as RoundedRectangleBorder)
            .side
            .color,
        dark.selectionOutline);
    await tester.tap(slot);
    await tester.pumpAndSettle();
    expect(tester.widget<Material>(material).color, dark.primary);
    await tester.tap(find.text(l.onboardingNextAlarms));
    await tester.pumpAndSettle();
    expectTheme(find.byType(AppUiCard).first);
    await tester.tap(find.text(l.onboardingEditAlarms).first);
    await tester.pumpAndSettle();
    expectTheme(find.byType(Dialog).last);
    expect(find.text(l.onboardingFixedAlarmDialogTitle(l.shiftDay)),
        findsOneWidget);
    await tester.tap(find.text(l.alarmAdd));
    await tester.pumpAndSettle();
    expect(find.byType(AlarmTimePicker), findsOneWidget);
    expectTheme(find.byType(AlarmTimePicker));
    expect(tester.takeException(), isNull);
  });
}
