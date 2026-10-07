import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/l10n/korean_only_copy.dart';
import 'package:shiftbell/l10n/l10n_extensions.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/screens/work_hours_settings_screen.dart';
import 'package:shiftbell/screens/help_screen.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:shiftbell/widgets/onboarding_info_popups.dart';
import 'package:shiftbell/widgets/public_web_load_failure.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const foreignLocales = [Locale('pt', 'BR'), Locale('de'), Locale('en'), Locale('hi')];

Widget host(ValueNotifier<Locale> language, Widget child) => ScreenUtilInit(
    designSize: const Size(360, 800),
    builder: (_, __) => ValueListenableBuilder<Locale>(
        valueListenable: language,
        builder: (_, locale, __) => MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: child)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.single;
    view.physicalSize = const Size(360, 800);
    view.devicePixelRatio = 1;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  testWidgets('foreign error details never expose internal Korean or another language', (tester) async {
    final language = ValueNotifier(const Locale('ko'));
    addTearDown(language.dispose);
    final error = StateError('저장 실패 / database is locked / Datenbankfehler');
    await tester.pumpWidget(host(language, Builder(builder: (context) =>
        Text(context.l10n.settingsScheduleChangeFailedWithError(context.localizedErrorDetail(error))))));
    await tester.pumpAndSettle();
    expect(find.textContaining(error.toString()), findsOneWidget);
    for (final locale in foreignLocales) {
      language.value = locale;
      await tester.pumpAndSettle();
      final l = lookupAppLocalizations(locale);
      expect(find.text(l.settingsScheduleChangeFailedWithError(l.statusErrorOccurred)), findsOneWidget);
      expect(find.textContaining(error.toString()), findsNothing);
    }
  });

  for (final failure in PublicWebLoadFailure.values) {
    testWidgets('public web $failure uses current language before and after async completion', (tester) async {
      final language = ValueNotifier(const Locale('ko'));
      addTearDown(language.dispose);
      final result = Completer<PublicWebLoadFailure>();
      await tester.pumpWidget(host(language, FutureBuilder<PublicWebLoadFailure>(
          future: result.future,
          builder: (_, snapshot) => snapshot.hasData
              ? PublicWebLoadFailurePage(failure: snapshot.data!)
              : const SizedBox.shrink())));
      language.value = foreignLocales.first;
      await tester.pumpAndSettle();
      result.complete(failure);
      for (final locale in foreignLocales) {
        language.value = locale;
        await tester.pumpAndSettle();
        final l = lookupAppLocalizations(locale);
        final reason = switch (failure) {
          PublicWebLoadFailure.missingCode => l.friendLinkMissingCode,
          PublicWebLoadFailure.unavailable => l.friendLoadFailedDetailed,
          PublicWebLoadFailure.unknown => l.friendUnknownError,
        };
        expect(find.text(l.friendCouldNotLoad), findsOneWidget);
        expect(find.text(reason), findsOneWidget);
        for (final text in tester.widgetList<Text>(find.byType(Text))) {
          expect(text.data, isNot(matches(RegExp('[가-힣]'))));
        }
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('a delayed Korean tutorial is not consumed after switching language', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final language = ValueNotifier(const Locale('ko'));
    addTearDown(language.dispose);
    late BuildContext screen;
    await tester.pumpWidget(host(language, Builder(builder: (context) {
      screen = context;
      return const Scaffold();
    })));
    await tester.pumpAndSettle();
    final pending = maybeShowScheduleTabTutorial(screen);
    await tester.pump();
    language.value = const Locale('hi');
    await tester.pump();
    await tester.pump(kInfoPopupDelay + const Duration(milliseconds: 1));
    await pending;
    expect(find.byType(Dialog), findsNothing);
    expect((await SharedPreferences.getInstance()).getBool('schedule_tab_tutorial_shown'), isNot(true));
  });

  testWidgets('an open common welcome popup changes to each current language', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final language = ValueNotifier(const Locale('ko'));
    addTearDown(language.dispose);
    late BuildContext screen;
    await tester.pumpWidget(host(language, Builder(builder: (context) {
      screen = context;
      return const Scaffold();
    })));
    await tester.pumpAndSettle();
    final pending = maybeShowWelcomePopup(screen);
    await tester.pump();
    await tester.pump(kInfoPopupDelay + const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    for (final locale in foreignLocales) {
      language.value = locale;
      await tester.pumpAndSettle();
      final text = tester.widgetList<RichText>(find.byType(RichText))
          .map((w) => w.text.toPlainText()).join(' ').replaceAll(RegExp(r'\s+'), ' ');
      expect(text, contains(lookupAppLocalizations(locale).onboardingWelcomePopupTitle));
      expect(text, isNot(matches(RegExp('[가-힣]'))));
    }
    await tester.tap(find.text(lookupAppLocalizations(language.value).onboardingWelcomePopupStartButton));
    await tester.pumpAndSettle();
    await pending;
  });

  testWidgets('legacy work-hour copy is Korean-only and changing language preserves stored hours', (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = Directory.systemTemp.createTempSync('locale_work_hours_');
    DatabaseService.debugIsAndroidOverride = false;
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      await databaseFactory.setDatabasesPath(directory.path);
      await DatabaseService.instance.saveShiftSchedule(ShiftSchedule(
          isRegular: true, pattern: const ['Day'], todayIndex: 0,
          startDate: DateTime(2026, 10, 6), shiftTypes: const ['Day'],
          shiftDurations: const {'Day': 480}));
    });
    final language = ValueNotifier(const Locale('ko'));
    addTearDown(language.dispose);
    await tester.pumpWidget(ProviderScope(child: host(language, const WorkHoursSettingsScreen())));
    await tester.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    final hint = KoreanOnlyCopy.forLocale('ko').workHoursLegacyClockTimeHint;
    expect(find.text(hint), findsOneWidget);
    for (final locale in foreignLocales) {
      language.value = locale;
      await tester.pumpAndSettle();
      expect(find.text(hint), findsNothing);
      expect(find.byKey(const ValueKey('legacy-shift-time-hint-Day')), findsNothing);
      expect(tester.takeException(), isNull);
    }
    language.value = const Locale('ko');
    await tester.pumpAndSettle();
    expect(find.text(hint), findsOneWidget);
    await tester.runAsync(() async {
      expect((await DatabaseService.instance.getShiftSchedule())!.shiftDurations, {'Day': 480});
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await (await DatabaseService.instance.database).close();
      DatabaseService.debugIsAndroidOverride = null;
      await directory.delete(recursive: true);
    });
  });

  testWidgets('old-version backup help remains Korean-only across search and an open detail', (tester) async {
    final language = ValueNotifier(const Locale('ko'));
    addTearDown(language.dispose);
    final copy = KoreanOnlyCopy.forLocale('ko');
    await tester.pumpWidget(host(language, const HelpScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), copy.helpBackupRestoreOldBackupFailTitle);
    await tester.pumpAndSettle();
    for (final locale in foreignLocales) {
      language.value = locale;
      await tester.pumpAndSettle();
      // The typed search query is user data and must not be translated or erased.
      expect(find.text(copy.helpBackupRestoreOldBackupFailTitle), findsOneWidget);
      expect(find.text(copy.helpBackupRestoreOldBackupFailBody), findsNothing);
    }
    language.value = const Locale('ko');
    await tester.pumpAndSettle();
    await tester.tap(find.text(copy.helpBackupRestoreOldBackupFailTitle).last);
    await tester.pumpAndSettle();
    expect(find.text(copy.helpBackupRestoreOldBackupFailBody), findsOneWidget);
    for (final locale in foreignLocales) {
      language.value = locale;
      await tester.pumpAndSettle();
      expect(find.text(copy.helpBackupRestoreOldBackupFailBody), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
