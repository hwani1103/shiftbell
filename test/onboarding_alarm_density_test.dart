import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/widgets/alarm_time_editor.dart';
import 'package:shiftbell/widgets/app_ui_components.dart';
import 'package:shiftbell/widgets/day_offset_chip.dart';
import 'onboarding_pattern_feedback_test.dart'
    show pumpOnboarding, snapshot, capture;

void main() {
  setUpAll(() async {
    if (capture) {
      for (final entry in {
        'FeedbackKorean': 'malgun.ttf',
        'FeedbackLatin': 'arial.ttf',
        'FeedbackHindi': 'Nirmala.ttf'
      }.entries) {
        final bytes =
            await File('C:/Windows/Fonts/' + entry.value).readAsBytes();
        await (FontLoader(entry.key)
              ..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
      }
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
    }
  });
  for (final regular in [true, false]) {
    testWidgets(
        'eight shifts with five alarms: ' + (regular ? 'regular' : 'irregular'),
        (tester) async {
      final boundary = GlobalKey();
      final l = await pumpOnboarding(
          tester, const Locale('ko'), const Size(400, 800), 1, boundary);
      Future<void> tap(String text) async {
        final f = find.text(text).last;
        await tester.ensureVisible(f);
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      for (var i = 0; i < 2; i++) {
        await tap(l.onboardingAddShiftName);
        await tester.enterText(find.byType(TextField), 'Z' + i.toString());
        await tap(l.commonAdd);
      }
      final heading = find.byKey(const ValueKey('onboarding-page-heading'));
      final firstHeading = tester.getRect(heading);
      final firstStyle = tester
          .widget<Text>(
              find.descendant(of: heading, matching: find.byType(Text)))
          .style;
      final firstChip = tester.getSize(find
          .descendant(
              of: find.byKey(const ValueKey('onboarding-shift-names')),
              matching: find.byType(AppUiShiftChip))
          .first);
      await snapshot(tester, boundary, 'names_consistent');
      await tap(l.onboardingNextPattern);
      expect(tester.getRect(heading).topLeft, firstHeading.topLeft);
      final nextStyle = tester
          .widget<Text>(
              find.descendant(of: heading, matching: find.byType(Text)))
          .style;
      expect(nextStyle?.fontSize, firstStyle?.fontSize);
      expect(nextStyle?.fontWeight, firstStyle?.fontWeight);
      final choices = find.byKey(const ValueKey('onboarding-shift-choices'));
      final chips =
          find.descendant(of: choices, matching: find.byType(AppUiShiftChip));
      expect(tester.getSize(chips.first), firstChip);
      final names = chips
          .evaluate()
          .map((e) => (e.widget as AppUiShiftChip).name)
          .toList();
      if (regular) {
        for (final name in names) {
          final f = find.descendant(of: choices, matching: find.text(name));
          await tester.ensureVisible(f);
          await tester.tap(f);
          await tester.pumpAndSettle();
        }
        await tap(l.onboardingCompletePattern);
        final slot = find.byKey(const ValueKey('onboarding-pattern-slot-0'));
        await tester.ensureVisible(slot);
        await tester.tap(slot);
        await tester.pumpAndSettle();
        await snapshot(tester, boundary, 'pattern_fixed_card');
        await tap(l.onboardingNextAlarms);
      } else {
        await tap(l.onboardingIrregularChoiceTitle);
      }
      for (var n = 0; n < names.length; n++) {
        final card = find.byKey(ValueKey('onboarding-alarm-card-' + names[n]));
        final chip =
            find.descendant(of: card, matching: find.byType(AppUiShiftChip));
        await tester.ensureVisible(chip);
        expect(tester.widget<AppUiShiftChip>(chip).onTap, isNull);
        await tester
            .tap(find.byKey(ValueKey('onboarding-alarm-edit-' + names[n])));
        await tester.pumpAndSettle();
        for (var i = 0; i < 5; i++) {
          await tap(l.alarmAdd);
          final picker = find.byType(AlarmTimePicker);
          await tester
              .widget<AlarmTimePicker>(picker)
              .onTimeSelected(TimeOfDay(hour: 6 + i, minute: n), i % 3 - 1);
          Navigator.of(tester.element(picker)).pop();
          await tester.pumpAndSettle();
        }
        final types = find.byType(AlarmTypeSelector);
        tester.widget<AlarmTypeSelector>(types.last).onChanged(3);
        await tester.pumpAndSettle();
        final add = find.ancestor(
            of: find.descendant(
                of: find.byType(Dialog), matching: find.text(l.alarmAdd)),
            matching: find.byType(AppUiButton));
        expect(tester.widget<AppUiButton>(add).onPressed, isNull);
        expect(find.text(l.commonSave).hitTestable(), findsOneWidget);
        expect(find.text(l.commonCancel).hitTestable(), findsOneWidget);
        if (n == 0)
          await snapshot(tester, boundary,
              (regular ? 'regular' : 'irregular') + '_five_alarm_dialog');
        await tap(l.commonSave);
        expect(find.descendant(of: card, matching: find.byType(DayOffsetBadge)),
            findsNWidgets(5));
        expect(find.descendant(of: card, matching: find.byType(Scrollable)),
            findsNothing);
        expect(tester.takeException(), isNull);
      }
      expect(find.byType(DayOffsetBadge), findsNWidgets(40));
      expect(find.text(l.onboardingFinishSetup).hitTestable(), findsOneWidget);
      await snapshot(tester, boundary,
          (regular ? 'regular' : 'irregular') + '_eight_shifts_five_alarms');
      expect(tester.takeException(), isNull);
    });
  }
  for (final entry in [
    ('de', const Size(320, 568)),
    ('ko', const Size(800, 360)),
    ('hi', const Size(320, 568))
  ]) {
    testWidgets(
        'five-alarm dialog and picker on ' +
            entry.$1 +
            ' ' +
            entry.$2.toString(), (tester) async {
      final key = GlobalKey();
      final l =
          await pumpOnboarding(tester, Locale(entry.$1), entry.$2, 2, key);
      Future<void> tap(String text) async {
        final f = find.text(text).last;
        await tester.ensureVisible(f);
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      await tap(l.onboardingNextPattern);
      await tap(l.onboardingIrregularChoiceTitle);
      await tap(l.onboardingEditAlarms);
      for (var i = 0; i < 5; i++) {
        await tap(l.alarmAdd);
        expect(tester.takeException(), isNull);
        if (i == 0)
          await snapshot(tester, key, entry.$1 + '_small_time_picker');
        final picker = find.byType(AlarmTimePicker);
        await tester
            .widget<AlarmTimePicker>(picker)
            .onTimeSelected(TimeOfDay(hour: 6 + i, minute: 0), i % 3 - 1);
        Navigator.of(tester.element(picker)).pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.text(l.commonSave).hitTestable(), findsOneWidget);
      await snapshot(tester, key, entry.$1 + '_small_five_alarm_dialog');
      await tap(l.commonSave);
      expect(tester.takeException(), isNull);
    });
  }
}
