import 'package:shiftbell/widgets/app_ui_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/screens/onboarding_screen.dart';
import 'package:shiftbell/widgets/alarm_time_editor.dart';
import 'package:shiftbell/widgets/app_ui_components.dart';
import 'package:shiftbell/theme/app_ui_theme.dart';

void main() {
  testWidgets(
      'onboarding fixed alarms save empty, cancel edits, cap five and allow re-add',
      (tester) async {
    SharedPreferences.setMockInitialValues({'welcome_popup_shown': true});
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        child: ScreenUtilInit(
      designSize: const Size(360, 780),
      builder: (_, __) => MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const OnboardingScreen()),
    )));
    await tester.pumpAndSettle();
    final l =
        AppLocalizations.of(tester.element(find.byType(OnboardingScreen)));
    Future<void> tapText(String text) async {
      await tester.ensureVisible(find.text(text).last);
      await tester.tap(find.text(text).last);
      if (text == l.onboardingCompletePattern) {
        await tester.pump();
        await tester.pump(AppUiMotion.transition);
      } else {
        await tester.pumpAndSettle();
      }
    }

    await tapText(l.onboardingNextPattern);
    final choice = find.descendant(
        of: find.byKey(const ValueKey('onboarding-shift-choices')),
        matching: find.text(l.shiftDay));
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
    }
    await tapText(l.onboardingCompletePattern);
    await tapText(l.shiftDay);
    await tapText(l.onboardingNextAlarms);
    expect(find.text('3 / 3'), findsOneWidget);
    await tapText(l.onboardingEditAlarms);
    expect(find.text(l.onboardingFixedAlarmDialogTitle(l.shiftDay)),
        findsOneWidget);
    Future<void> add(int hour, int minute, int offset) async {
      await tapText(l.alarmAdd);
      final finder = find.byType(AlarmTimePicker);
      final picker = tester.widget<AlarmTimePicker>(finder);
      // All hour/offset input controls are independently exercised by alarm_time_format_test.
      // Here the actual onboarding callback and dialog state are the subject.
      await picker.onTimeSelected(
          TimeOfDay(hour: hour, minute: minute), offset);
      Navigator.of(tester.element(finder)).pop();
      await tester.pumpAndSettle();
    }

    await add(0, 0, -1);
    await tapText(l.commonSave);
    await tapText(l.onboardingEditAlarms);
    expect(
        find.descendant(of: find.byType(Dialog), matching: find.text('00:00')),
        findsOneWidget);
    await tester.tap(find.byIcon(AppUiIcons.delete).first);
    await tester.pumpAndSettle();
    await tapText(l.commonCancel);
    await tapText(l.onboardingEditAlarms);
    expect(
        find.descendant(of: find.byType(Dialog), matching: find.text('00:00')),
        findsOneWidget,
        reason: 'cancel must retain the saved alarm');
    await add(0, 0, 0);
    await add(0, 0, 1);
    await add(23, 59, -1);
    await add(23, 59, 0);
    expect(find.byIcon(AppUiIcons.delete), findsNWidgets(5));
    final addButton = find.ancestor(
        of: find.text(l.alarmAdd), matching: find.byType(AppUiButton));
    expect(tester.widget<AppUiButton>(addButton).onPressed, isNull);
    await tester.tap(find.byIcon(AppUiIcons.delete).first);
    await tester.pumpAndSettle();
    await add(23, 59, 1);
    expect(find.byIcon(AppUiIcons.delete), findsNWidgets(5));
    while (find.byIcon(AppUiIcons.delete).evaluate().isNotEmpty) {
      await tester.ensureVisible(find.byIcon(AppUiIcons.delete).first);
      await tester.tap(find.byIcon(AppUiIcons.delete).first);
      await tester.pumpAndSettle();
    }
    await tapText(l.commonSave);
    await tapText(l.onboardingEditAlarms);
    expect(find.byIcon(AppUiIcons.delete), findsNothing,
        reason: 'empty selection must save');
    await tapText(l.commonCancel);
    expect(tester.takeException(), isNull);
  });
}
