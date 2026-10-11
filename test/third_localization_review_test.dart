import 'package:shiftbell/l10n/korean_only_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/screens/help_screen.dart';
import 'package:shiftbell/models/calendar_theme.dart';
import 'package:shiftbell/widgets/onboarding_info_popups.dart';

const locales = [Locale('pt', 'BR'), Locale('de', 'DE'), Locale('en', 'US'), Locale('hi', 'IN')];

Widget harness(Locale locale, Widget child) => ScreenUtilInit(
  designSize: const Size(411, 891),
  builder: (_, __) => MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('ko'), ...locales],
    localizationsDelegates: const [AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate],
    home: child,
  ),
);

void main() {
  test('one-day cycles and one failed alarm use singular forms', () async {
    final pt = await AppLocalizations.delegate.load(locales[0]);
    final de = await AppLocalizations.delegate.load(locales[1]);
    final hi = await AppLocalizations.delegate.load(locales[3]);
    expect(pt.statusPatternDayCycle(1), contains('1 dia)'));
    expect(pt.statusPatternDayCycle(2), contains('2 dias)'));
    expect(de.statusPatternDayCycle(1), contains('1-Tag-Zyklus'));
    expect(de.statusPatternDayCycle(2), contains('2-Tage-Zyklus'));
    expect(pt.alarmSchedulePartialFailed(1, 3), contains('1 de 3 alarmes não pôde'));
    expect(pt.alarmSchedulePartialFailed(2, 3), contains('2 de 3 alarmes não puderam'));
    expect(de.alarmSchedulePartialFailed(1, 3), contains('1 von 3 Weckern konnte'));
    expect(de.alarmSchedulePartialFailed(2, 3), contains('2 von 3 Weckern konnten'));
    expect(hi.alarmSchedulePartialFailed(1, 3), contains('3 में से 1 अलार्म सेट नहीं हुआ'));
    expect(hi.alarmSchedulePartialFailed(2, 3), contains('3 में से 2 अलार्म सेट नहीं हुए'));
  });

  for (final locale in locales) {
    testWidgets('$locale never opens sleep or personal-event tutorials', (tester) async {
      late BuildContext appContext;
      await tester.pumpWidget(harness(locale, Builder(builder: (context) {
        appContext = context;
        return const SizedBox.shrink();
      })));
      await maybeShowConditionTabTutorial(appContext);
      await maybeShowScheduleTabTutorial(appContext);
      await tester.pump(kInfoPopupDelay);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });

    test('$locale public copy describes only available features', () async {
      final l = await AppLocalizations.delegate.load(locale);
      final publicCopy = [l.privacyIntro, l.privacyNoCollectionBody,
        l.privacyFirebaseTitle, l.privacyFirebaseBody, l.privacyDataRetentionBody,
        l.helpBackupDataStorageBody, l.helpDiagnosticBody, l.helpCalendarLocaleBody,
        l.helpCalendarHomeWidgetBody,
        l.settingsResetScheduleConfirm, l.settingsAllAlarmsWillBeDeleted,
        l.settingsScheduleChangeWarning].join('\n');
      expect(publicCopy, isNot(matches(RegExp(
        r'Korean|coreano|koreanisch|कोरियाई|sleep|sono|Schlaf|नींद|one.tap|Schnellwecker|alarme rápido|एक टैप|friend|amigos|Freund|दोस्त',
        caseSensitive: false))));
      expect(l.privacyFirebaseBody, contains('Google Play'));
      expect(l.privacyDataRetentionBody, contains('Download/ShiftBell'));
    });

    testWidgets('$locale help search excludes unavailable features', (tester) async {
      await tester.pumpWidget(harness(locale, const HelpScreen()));
      await tester.pumpAndSettle();
      final l = await AppLocalizations.delegate.load(locale);
      for (final title in [KoreanOnlyCopy.forLocale('ko').helpConditionWhatIsItTitle, KoreanOnlyCopy.forLocale('ko').helpSleepWidgetTitle,
        KoreanOnlyCopy.forLocale('ko').helpScheduleTabWhatIsItTitle, KoreanOnlyCopy.forLocale('ko').helpFriendWhatIsItTitle,
        KoreanOnlyCopy.forLocale('ko').helpTroubleshootFriendDisconnectedTitle]) {
        await tester.enterText(find.byType(TextField), title);
        await tester.pump();
        expect(find.text(title), findsOneWidget); // Search input only.
        expect(find.text(l.helpEmptySearchResult), findsOneWidget);
      }
    });

    testWidgets('$locale hides an already-open Korean-only help detail', (tester) async {
      final language = ValueNotifier(const Locale('ko'));
      addTearDown(language.dispose);
      await tester.pumpWidget(ValueListenableBuilder<Locale>(
        valueListenable: language,
        builder: (_, locale, __) => harness(locale, HelpDetailScreen(
          koreanOnly: true,
          topic: HelpTopic(titleKey: (l) => KoreanOnlyCopy.forLocale('ko').helpSleepWidgetTitle,
            bodyKey: (l) => KoreanOnlyCopy.forLocale('ko').helpSleepWidgetBody),
        )),
      ));
      await tester.pumpAndSettle();
      expect(find.text(KoreanOnlyCopy.forLocale('ko').helpSleepWidgetBody), findsOneWidget);
      language.value = locale;
      await tester.pumpAndSettle();
      expect(find.text(KoreanOnlyCopy.forLocale('ko').helpSleepWidgetBody), findsNothing);
      expect(find.byType(HelpScreen), findsOneWidget);
    });

    testWidgets('$locale excludes a Korean-only detail opened through search', (tester) async {
      final language = ValueNotifier(const Locale('ko'));
      addTearDown(language.dispose);
      await tester.pumpWidget(ValueListenableBuilder<Locale>(
        valueListenable: language,
        builder: (_, locale, __) => harness(locale, const HelpScreen()),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), KoreanOnlyCopy.forLocale('ko').helpSleepWidgetTitle);
      await tester.pump();
      await tester.tap(find.text(KoreanOnlyCopy.forLocale('ko').helpSleepWidgetTitle).last);
      await tester.pumpAndSettle();
      expect(find.text(KoreanOnlyCopy.forLocale('ko').helpSleepWidgetBody), findsOneWidget);
      language.value = locale;
      await tester.pumpAndSettle();
      expect(find.text(KoreanOnlyCopy.forLocale('ko').helpSleepWidgetBody), findsNothing);
    });

    testWidgets('$locale limits themes without replacing stored Korean choices', (tester) async {
      late List<CalendarThemeId> available;
      late CalendarThemeId fallback;
      await tester.pumpWidget(harness(locale, Builder(builder: (context) {
        available = context.availableCalendarThemes;
        fallback = context.availableCalendarTheme(CalendarThemeId.editorial);
        return const SizedBox.shrink();
      })));
      await tester.pumpAndSettle();
      expect(available, hasLength(7));
      expect(available.take(2), [CalendarThemeId.periwinkle, CalendarThemeId.softMosaic]);
      expect(available, isNot(contains(CalendarThemeId.diary)));
      expect(available, isNot(contains(CalendarThemeId.editorial)));
      expect(available, isNot(contains(CalendarThemeId.initialBadge)));
      expect(available, isNot(contains(CalendarThemeId.eventChip)));
      expect(available, isNot(contains(CalendarThemeId.underline)));
      expect(fallback, CalendarThemeId.periwinkle);
    });
  }
}
