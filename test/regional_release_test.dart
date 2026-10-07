import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/l10n/release_locale.dart';
import 'package:shiftbell/l10n/regional_material_localizations.dart';
import 'package:shiftbell/utils/weekday_util.dart';
import 'package:intl/intl.dart';
import 'package:shiftbell/utils/holiday_util.dart';
import 'package:shiftbell/models/friend_schedule.dart';
import 'package:shiftbell/widgets/friend_web_calendar.dart';
import 'package:table_calendar/table_calendar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('English region survives language fallback and ignores secondary Korean',
      () {
    for (final region in ['US', 'GB', 'ZA', 'IN', 'AE', 'PH']) {
      for (final language in ['en', 'xx']) {
        expect(
            resolveReleaseLocale(
                [Locale(language, region), const Locale('ko', 'KR')],
                releaseSupportedLocales),
            Locale('en', region));
      }
    }
    expect(
        resolveReleaseLocale(
            [const Locale('hi', 'IN')], releaseSupportedLocales),
        const Locale('hi', 'IN'));
  });
  test('regional date formatting, parsing, input hints and week starts agree',
      () async {
    for (final row in [
      ('US', 0, '4/5/2026'),
      ('GB', 1, '05/04/2026'),
      ('ZA', 0, '2026/04/05'),
      ('IN', 0, '5/4/2026'),
      ('AE', 1, '4/5/2026'),
      ('PH', 0, '4/5/2026')
    ]) {
      final locale = Locale('en', row.$1);
      final delegate = releaseRegionalMaterialDelegate.isSupported(locale)
          ? releaseRegionalMaterialDelegate
          : GlobalMaterialLocalizations.delegate;
      final m = await delegate.load(locale);
      expect(m.firstDayOfWeekIndex, row.$2, reason: locale.toString());
      expect(m.formatCompactDate(DateTime(2026, 4, 5)), row.$3);
      expect(m.parseCompactDate(row.$3), DateTime(2026, 4, 5));
      expect(m.formatTimeOfDay(const TimeOfDay(hour: 13, minute: 5)),
          ['GB', 'ZA'].contains(row.$1) ? '13:05' : '1:05 PM');
      if (row.$1 == 'ZA') expect(m.dateHelpText, 'yyyy/mm/dd');
      expect(DateFormat.yMd(locale.toString()).format(DateTime(2026, 4, 5)),
          row.$3);
      expect(getHolidayName(DateTime(2026, 10, 9), isKorean: false), isNull);
    }
  });
  testWidgets(
      'public web header follows current language and regional weekday order',
      (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = FriendScheduleData(
        ownerName: 'Original user text',
        isRegular: false,
        shiftColors: const {},
        assignedDates: const {},
        updatedAt: DateTime(2026, 10, 6));
    for (final c in [
      (const Locale('en', 'US'), 'Mon', StartingDayOfWeek.sunday),
      (const Locale('en', 'GB'), 'Mon', StartingDayOfWeek.monday),
      (const Locale('en', 'ZA'), 'Mon', StartingDayOfWeek.sunday),
      (const Locale('en', 'IN'), 'Mon', StartingDayOfWeek.sunday),
      (const Locale('en', 'PH'), 'Mon', StartingDayOfWeek.sunday),
      (const Locale('en', 'AE'), 'Mon', StartingDayOfWeek.monday),
      (const Locale('de', 'DE'), 'Mo', StartingDayOfWeek.monday),
      (const Locale('pt', 'BR'), 'seg', StartingDayOfWeek.sunday),
      (const Locale('hi', 'IN'), 'सोम', StartingDayOfWeek.sunday),
      (const Locale('ko'), '월', StartingDayOfWeek.sunday)
    ]) {
      await tester.pumpWidget(MaterialApp(
          locale: c.$1,
          supportedLocales: releaseSupportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            releaseRegionalMaterialDelegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          home: Scaffold(
              body: FriendWebCalendar(
                  friendName: data.ownerName,
                  data: data,
                  initialDay: DateTime(2026, 10, 6),
                  showPwaAddressBarHint: false,
                  showQuickInstallButton: false,
                  showInstallPrompt: false))));
      await tester.pumpAndSettle();
      final calendar = tester.widget<TableCalendar>(find.byType(TableCalendar));
      expect(calendar.locale, c.$1.toString());
      expect(calendar.startingDayOfWeek, c.$3);
      if (c.$1.languageCode != 'en') expect(find.text('Mon'), findsNothing);
      expect(find.textContaining(RegExp('^${RegExp.escape(c.$2)}' r'\.?$')),
          findsOneWidget);
      expect(find.textContaining(data.ownerName), findsOneWidget);
      // The actual datepicker uses the same Material delegate as the calendar.
      final context = tester.element(find.byType(FriendWebCalendar));
      expect(MaterialLocalizations.of(context).firstDayOfWeekIndex,
          c.$3 == StartingDayOfWeek.monday ? 1 : 0);
      expect(weekdayLabel(context, 1), isNotEmpty);
    }
  });
}
