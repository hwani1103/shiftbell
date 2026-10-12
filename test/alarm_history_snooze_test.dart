import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/alarm_history.dart';

void main() {
  for (final (locale, expected, unknown) in [
    (const Locale('ko'), '15분 연장', '연장'),
    (const Locale('en'), 'Snoozed for 15 min', 'Snoozed'),
    (const Locale('de'), 'Um 15 Minuten verschoben', 'Verschoben'),
    (const Locale('pt'), 'Adiado por 15 minutos', 'Adiado'),
    (const Locale('hi'), '15 मिनट के लिए स्नूज़ किया गया', 'स्नूज़ किया गया'),
  ]) {
  testWidgets('$locale history keeps the executed duration; unknown legacy duration is not invented', (tester) async {
    final history = AlarmHistory.fromMap({
      'alarm_id': 7,
      'scheduled_time': '09:00',
      'scheduled_date': '2026-10-07T09:00:00',
      'actual_ring_time': '2026-10-07T09:00:03',
      'created_at': '2026-10-07T09:00:03',
      'dismiss_type': 'snoozed',
      'snooze_minutes': 15,
    });
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(builder: (context) => Text(history.dismissLabel(context))),
    ));
    await tester.pumpAndSettle();
    expect(find.text(expected), findsOneWidget);
    expect(history.snoozeMinutes, 15);
    final legacy = AlarmHistory.fromMap({
      'alarm_id': 8, 'scheduled_time': '09:00',
      'scheduled_date': '2026-10-07T09:00:00',
      'actual_ring_time': '2026-10-07T09:00:03',
      'created_at': '2026-10-07T09:00:03', 'dismiss_type': 'snoozed',
    });
    expect(legacy.snoozeMinutes, isNull);
    final context = tester.element(find.text(expected));
    expect(legacy.dismissLabel(context), unknown);
  });
  }
}
