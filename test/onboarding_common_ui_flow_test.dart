import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/widgets/app_ui_components.dart';
import 'onboarding_pattern_feedback_test.dart' show pumpOnboarding;

void main() {
  for (final code in ['ko', 'en', 'de', 'pt', 'hi']) {
    testWidgets(
        '$code: names validate inline and repeated positions select exactly today',
        (tester) async {
      final l = await pumpOnboarding(
          tester, Locale(code), const Size(360, 640), 1, GlobalKey());
      expect(find.text(l.onboardingBackupTitle), findsNothing);
      await tester.ensureVisible(find.text(l.onboardingAddShiftName));
      await tester.tap(find.text(l.onboardingAddShiftName));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.commonAdd));
      await tester.pumpAndSettle();
      expect(find.byType(AppUiDialog), findsOneWidget);
      expect(
          tester
              .widget<TextField>(find.byType(TextField))
              .decoration!
              .errorText,
          isNotNull);
      await tester.enterText(find.byType(TextField), l.shiftDay);
      await tester.tap(find.text(l.commonAdd));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextField>(find.byType(TextField))
              .decoration!
              .errorText,
          isNotNull);
      await tester.enterText(find.byType(TextField), 'ZZ');
      await tester.tap(find.text(l.commonAdd));
      await tester.pumpAndSettle();
      expect(find.byType(AppUiDialog), findsNothing);
      expect(find.text('ZZ'), findsOneWidget);
      await tester.tap(find.text(l.onboardingNextPattern));
      await tester.pumpAndSettle();
      final choices = find.byKey(const ValueKey('onboarding-shift-choices'));
      final day = find.descendant(of: choices, matching: find.text(l.shiftDay));
      await tester.ensureVisible(day);
      await tester.tap(day);
      await tester.pumpAndSettle();
      await tester.tap(day);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(l.onboardingCompletePattern));
      await tester.tap(find.text(l.onboardingCompletePattern));
      await tester.pumpAndSettle();
      final second = find.byKey(const ValueKey('onboarding-pattern-slot-1'));
      await tester.ensureVisible(second);
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(find.text(l.onboardingEditPattern), findsOneWidget);
      expect(tester.widget<AppUiShiftChip>(second).selectionMode, isTrue);
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('onboarding-pattern-slot-1')),
          findsOneWidget,
          reason: 'Today selection must never delete the pattern');
      expect(tester.widget<AppUiShiftChip>(second).selected, isTrue);
      expect(
          tester
              .widget<AppUiShiftChip>(
                  find.byKey(const ValueKey('onboarding-pattern-slot-0')))
              .selected,
          isFalse);
      expect(find.text(l.onboardingTodayMarker), findsOneWidget);
      expect(day, findsOneWidget,
          reason: 'Today selection keeps shift choices on the same screen');
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.tap(find.text(l.onboardingNextAlarms));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(tester.widget<AppUiShiftChip>(second).selected, isTrue);
      expect(tester.widget<AppUiShiftChip>(second).selectionMode, isTrue);
      await tester.ensureVisible(find.text(l.onboardingEditPattern));
      await tester.tap(find.text(l.onboardingEditPattern));
      await tester.pumpAndSettle();

      await tester.ensureVisible(second);
      await tester.tap(second);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(l.onboardingCompletePattern));
      await tester.tap(find.text(l.onboardingCompletePattern));
      await tester.pumpAndSettle();
      final button = tester.widget<AppUiButton>(find.ancestor(
          of: find.text(l.onboardingNextAlarms),
          matching: find.byType(AppUiButton)));
      expect(
          tester
              .widget<AppUiShiftChip>(
                  find.byKey(const ValueKey('onboarding-pattern-slot-0')))
              .selectionMode,
          isFalse);
      expect(find.text(l.onboardingTodayPositionHint), findsNothing);
      expect(button.onPressed, isNull,
          reason: 'Editing the order must invalidate the old today position');
      expect(tester.takeException(), isNull);
    });
  }
}
