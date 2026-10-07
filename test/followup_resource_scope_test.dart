import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/l10n/korean_only_copy.dart';
import 'package:shiftbell/l10n/release_locale.dart';
import 'package:shiftbell/models/friend_schedule.dart';
import 'package:shiftbell/screens/friend_calendar_view.dart';
import 'package:shiftbell/screens/friend_list_screen.dart';
import 'package:shiftbell/screens/my_share_code_screen.dart';
import 'package:shiftbell/screens/condition_tab.dart';
import 'package:shiftbell/screens/schedule_management_tab.dart';
import 'package:shiftbell/widgets/calendar_header_actions.dart';
import 'package:shiftbell/widgets/friend_web_calendar.dart';
import 'package:shiftbell/widgets/unavailable_feature.dart';
import 'package:shiftbell/services/holiday_sync_service.dart';
import 'package:shiftbell/utils/holiday_util.dart';
import 'package:shiftbell/constants/platform_channel.dart';

Widget host(Locale locale, Widget child) => ProviderScope(
    child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeDateFormatting);
  test('native app and public web use English fallback and the same regional policy', () {
    for (final locale in [const Locale('es'),const Locale('ja'),const Locale('fr')]) {
      expect(resolveReleaseLocale([locale],releaseSupportedLocales), const Locale('en','US'));
    }
    expect(resolveReleaseLocale(null,releaseSupportedLocales),const Locale('en','US'));
    expect(resolveReleaseLocale([const Locale('fr','FR')],releaseSupportedLocales),const Locale('en','GB'));
    expect(resolveReleaseLocale([const Locale('pt','PT')],releaseSupportedLocales),const Locale('pt','BR'));
  });
  final data = FriendScheduleData(
      ownerName: 'Test',
      isRegular: true,
      pattern: ['Day'],
      todayIndex: 0,
      startDate: DateTime(2026, 10, 1),
      shiftColors: const {},
      assignedDates: const {},
      updatedAt: DateTime(2026, 10, 1));
  for (final locale in [
    const Locale('pt', 'BR'),
    const Locale('de'),
    const Locale('en'),
    const Locale('hi')
  ]) {
    testWidgets('$locale shared header localizes public actions and blocks hidden callbacks', (tester) async {
      var forbiddenCalls = 0;
      var teamCalls = 0;
      await tester.pumpWidget(host(locale, Scaffold(body: CalendarHeaderActions(
        onToday: () {}, onAllShifts: () => teamCalls++,
        onFriends: () => forbiddenCalls++,
        isKorean: true, editorial: false))));
      await tester.pumpAndSettle();
      final l = lookupAppLocalizations(locale);
      expect(find.text(l.commonToday.toUpperCase()), findsOneWidget);
      expect(find.text('일정공유'), findsNothing);
      expect(find.byIcon(Icons.alarm_add_rounded), findsNothing);
      await tester.tap(find.text(l.shiftFullSchedule));
      expect(teamCalls, 1);
      expect(forbiddenCalls, 0);
    });
    test('$locale Korean-only resources refuse fallback', () {
      expect(() => KoreanOnlyCopy.forLocale(locale.languageCode),
          throwsStateError);
    });
    testWidgets(
        '$locale app routes are blocked but public web calendar is retained',
        (tester) async {
      for (final child in <Widget>[
        const FriendListScreen(),
        const MyShareCodeScreen(),
        ConditionTab(onDisabled: () {}, onConfirmed: () async {}),
        ScheduleManagementTab(onDisabled: () {}, onConfirmed: () async {}),
        FriendCalendarView(friendName: 'Test', data: data)
      ]) {
        await tester.pumpWidget(host(locale, child));
        await tester.pumpAndSettle();
        expect(find.byType(UnavailableFeature), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(host(
          locale,
          FriendCalendarView(
              friendName: 'Test',
              data: data,
              publicWebViewer: true,
              showInstallPrompt: true,
              showPwaAddressBarHint: false)));
      await tester.pumpAndSettle();
      expect(find.byType(FriendWebCalendar), findsOneWidget);
      expect(find.byType(UnavailableFeature), findsNothing);
      expect(tester.takeException(), isNull);
    });
    test(
        '$locale holiday cache and refresh do not change foreign-install preferences',
        () async {
      SharedPreferences.setMockInitialValues({});
      final dispatcher =
          TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;
      dispatcher.localeTestValue = locale;
      addTearDown(dispatcher.clearLocaleTestValue);
      await HolidaySyncService.instance.loadCached();
      await HolidaySyncService.instance.refreshIfDue();
      final before = HolidayOverrides.current;
      await HolidaySyncService.instance.apply(HolidayOverrides.fromJson({
        'add': {'2026-10-10': '한국어 전용 공휴일'},
      }));
      expect(HolidayOverrides.current, same(before));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });
  }
  test('Korean resources and holiday application are preserved', () async {
    expect(
        KoreanOnlyCopy.forLocale('ko').helpTroubleshootFriendDisconnectedTitle, isNotEmpty);
    SharedPreferences.setMockInitialValues({});
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.localeTestValue = const Locale('ko');
    final before = HolidayOverrides.current;
    addTearDown(() {
      binding.platformDispatcher.clearLocaleTestValue();
      HolidayOverrides.current = before;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(kAlarmChannel, null);
    });
    final calls = <String>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      calls.add(call.method);
      return null;
    });
    final overrides = HolidayOverrides.fromJson({
      'add': {'2026-10-10': '추가 공휴일'},
    });
    await HolidaySyncService.instance.apply(overrides);
    expect(HolidayOverrides.current, same(overrides));
    expect((await SharedPreferences.getInstance()).getString(
        HolidaySyncService.cachePrefKey), contains('추가 공휴일'));
    expect(calls, contains('setHolidayOverrides'));
  });
}
