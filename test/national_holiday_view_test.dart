import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/friend_schedule.dart';
import 'package:shiftbell/widgets/friend_web_calendar.dart';

void main() {
  testWidgets('foreign holiday is a red date with a tappable name, without a cell label', (tester) async {
    await initializeDateFormatting();
    tester.binding.platformDispatcher.localeTestValue = const Locale('en', 'US');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en', 'US'),
      supportedLocales: const [Locale('en', 'US')],
      localizationsDelegates: const [AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate],
      home: FriendWebCalendar(friendName: 'Test', initialDay: DateTime(2026, 11, 1),
        showPwaAddressBarHint: false, showQuickInstallButton: false,
        data: FriendScheduleData(ownerName: 'Test', isRegular: true,
          pattern: ['Day'], todayIndex: 0, startDate: DateTime(2026, 11, 1),
          shiftColors: const {'Day': 0xFF476DCD}, assignedDates: const {},
          updatedAt: DateTime(2026, 11, 1))),
    ));
    await tester.pumpAndSettle();
    final sunday = find.byKey(const ValueKey('friend-date-2026-11-08'));
    expect(tester.widget<Text>(sunday).style!.color, const Color(0xFF202124));
    final date = find.byKey(const ValueKey('friend-date-2026-11-26'));
    expect(tester.widget<Text>(date).style!.color, Colors.red.shade600);
    expect(find.byKey(const ValueKey('friend-holiday-2026-11-26')), findsNothing);
    expect(find.text('Thanksgiving Day'), findsNothing);
    await tester.tap(date);
    await tester.pumpAndSettle();
    expect(find.text('Thanksgiving Day'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
