import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/alarm.dart';
import 'package:shiftbell/widgets/calendar_snoozed_alarms.dart';

Alarm reservation(int id, DateTime? date, {String type = 'snoozed'}) => Alarm(
      id: id,
      // Original slot deliberately differs from the actual snooze time.
      time: '23:58',
      date: date,
      type: type,
      alarmTypeId: 1,
      dayOffset: -1,
      fixedSlotTime: '23:58',
    );

Widget host(DateTime day, List<Alarm> alarms, {String language = 'ko'}) =>
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, child) => MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 280,
              child: CalendarSnoozedAlarms(day: day, alarms: alarms),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
      'uses retry date across midnight, ignores fixed/custom/null dates',
      (tester) async {
    final alarms = [
      reservation(1, DateTime(2026, 10, 10, 0, 3)),
      reservation(2, DateTime(2026, 10, 10, 1), type: 'fixed'),
      reservation(3, DateTime(2026, 10, 10, 2), type: 'custom'),
      reservation(4, null),
    ];
    await tester.pumpWidget(host(DateTime(2026, 10, 9), alarms));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.snooze_rounded), findsNothing);
    expect(find.text('다시 알림'), findsNothing);

    await tester.pumpWidget(host(DateTime(2026, 10, 10), alarms));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.snooze_rounded), findsOneWidget);
    expect(find.text('00:03'), findsOneWidget);
    expect(find.text('23:58'), findsNothing);
    expect(find.byKey(const ValueKey('calendar-snoozed-2')), findsNothing);
    expect(find.byKey(const ValueKey('calendar-snoozed-3')), findsNothing);
  });

  testWidgets('live reservation changes replace time and remove empty section',
      (tester) async {
    final day = DateTime(2026, 10, 9);
    await tester
        .pumpWidget(host(day, [reservation(1, DateTime(2026, 10, 9, 9, 5))]));
    await tester.pumpAndSettle();
    expect(find.text('09:05'), findsOneWidget);
    await tester
        .pumpWidget(host(day, [reservation(1, DateTime(2026, 10, 9, 9, 10))]));
    await tester.pumpAndSettle();
    expect(find.text('09:05'), findsNothing);
    expect(find.text('09:10'), findsOneWidget);
    await tester.pumpWidget(host(day, []));
    await tester.pumpAndSettle();
    expect(find.text('다시 알림'), findsNothing);
    expect(find.byIcon(Icons.snooze_rounded), findsNothing);
  });

  testWidgets('sorts by retry instant and cards have no editing action',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final alarms = [
      reservation(2, DateTime(2026, 10, 9, 9, 10)),
      reservation(1, DateTime(2026, 10, 9, 9, 5)),
    ];
    await tester.pumpWidget(host(DateTime(2026, 10, 9), alarms));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('09:05')).dx,
        lessThan(tester.getTopLeft(find.text('09:10')).dx));
    final card = find.byKey(const ValueKey('calendar-snoozed-1'));
    expect(
        tester
            .getSemantics(card)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse);
    semantics.dispose();
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(alarms.map((a) => a.id), [2, 1]);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ko', 'en', 'de', 'pt', 'hi']) {
    testWidgets(
        '$language cards fit a narrow viewport with multiple reservations',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(host(
        DateTime(2026, 10, 9),
        [
          for (var i = 0; i < 5; i++)
            reservation(i, DateTime(2026, 10, 9, 9, i * 5))
        ],
        language: language,
      ));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.snooze_rounded), findsNWidgets(5));
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
