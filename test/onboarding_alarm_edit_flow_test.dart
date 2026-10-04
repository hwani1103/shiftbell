import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/screens/onboarding_screen.dart';
import 'package:shiftbell/widgets/alarm_time_editor.dart';
import 'package:shiftbell/widgets/app_third_button.dart';

void main() {
  testWidgets('onboarding fixed alarms save empty, cancel edits, cap five and allow re-add', (tester) async {
    SharedPreferences.setMockInitialValues({'welcome_popup_shown': true});
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(child: ScreenUtilInit(
      designSize: const Size(360, 780),
      builder: (_, __) => MaterialApp(locale: const Locale('ko'),
        localizationsDelegates: const [AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales, home: const OnboardingScreen()),
    )));
    await tester.pumpAndSettle();
    final l = AppLocalizations.of(tester.element(find.byType(OnboardingScreen)));
    Future<void> tapText(String text) async {
      await tester.ensureVisible(find.text(text).last);
      await tester.tap(find.text(text).last);
      await tester.pumpAndSettle();
    }
    await tapText(l.commonNext);
    await tapText(l.shiftDay);
    await tapText(l.commonNext);
    await tapText(l.shiftDay);
    await tapText(l.commonNext);
    expect(find.text('4 / 4'), findsOneWidget);
    await tapText(l.shiftDay);
    expect(find.text(l.onboardingFixedAlarmDialogTitle(l.shiftDay)), findsOneWidget);
    Future<void> add(int hour, int minute, int offset) async {
      await tapText(l.alarmAdd);
      final finder = find.byType(AlarmTimePicker);
      final picker = tester.widget<AlarmTimePicker>(finder);
      // All hour/offset input controls are independently exercised by alarm_time_format_test.
      // Here the actual onboarding callback and dialog state are the subject.
      await picker.onTimeSelected(TimeOfDay(hour: hour, minute: minute), offset);
      Navigator.of(tester.element(finder)).pop();
      await tester.pumpAndSettle();
    }
    await add(0, 0, -1);
    await tapText(l.commonSave);
    await tapText(l.shiftDay);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('00:00')), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pumpAndSettle();
    await tapText(l.commonCancel);
    await tapText(l.shiftDay);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('00:00')), findsOneWidget,
        reason: 'cancel must retain the saved alarm');
    await add(0, 0, 0);
    await add(0, 0, 1);
    await add(23, 59, -1);
    await add(23, 59, 0);
    expect(find.byIcon(Icons.delete), findsNWidgets(5));
    final addButton = find.ancestor(of: find.text(l.alarmAdd), matching: find.byType(AppThirdButton));
    expect(tester.widget<AppThirdButton>(addButton).onPressed, isNull);
    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pumpAndSettle();
    await add(23, 59, 1);
    expect(find.byIcon(Icons.delete), findsNWidgets(5));
    while (find.byIcon(Icons.delete).evaluate().isNotEmpty) {
      await tester.ensureVisible(find.byIcon(Icons.delete).first);
      await tester.tap(find.byIcon(Icons.delete).first);
      await tester.pumpAndSettle();
    }
    await tapText(l.commonSave);
    await tapText(l.shiftDay);
    expect(find.byIcon(Icons.delete), findsNothing, reason: 'empty selection must save');
    await tapText(l.commonCancel);
    expect(tester.takeException(), isNull);
  });
}
