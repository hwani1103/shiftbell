import 'package:shiftbell/providers/app_ui_theme_preview_provider.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/screens/onboarding_screen.dart';
import 'package:shiftbell/theme/app_theme.dart';
import 'package:shiftbell/theme/app_ui_theme.dart';
import 'package:shiftbell/widgets/app_content_frame.dart';
import 'package:shiftbell/constants/layout_limits.dart';
import 'package:shiftbell/widgets/app_shift_chip.dart';
import 'package:shiftbell/widgets/app_ui_components.dart';

const capture = bool.fromEnvironment('CAPTURE_ONBOARDING_FEEDBACK');
final _choices = find.byKey(const ValueKey('onboarding-shift-choices'));
final _preview = find.byKey(const ValueKey('onboarding-pattern-preview'));

Future<void> snapshot(WidgetTester tester, GlobalKey key, String name) async {
  if (!capture) return;
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final picture = await boundary.toImage(pixelRatio: 2);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory(const String.fromEnvironment(
        'ONBOARDING_CAPTURE_DIR',
        defaultValue: 'artifacts/onboarding_theme_2026_10_09/host'));
    await folder.create(recursive: true);
    await File('${folder.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

Future<AppLocalizations> pumpOnboarding(WidgetTester tester, Locale locale,
    Size size, double scale, GlobalKey boundary,
    {AppUiPalette? palette,
    bool reduceMotion = true,
    DateTime Function()? clock,
    bool resetPreferences = true}) async {
  if (resetPreferences) SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final family = locale.languageCode == 'ko'
      ? 'FeedbackKorean'
      : locale.languageCode == 'hi'
          ? 'FeedbackHindi'
          : 'FeedbackLatin';
  await tester.pumpWidget(ProviderScope(
      overrides: [
        appUiThemePaletteOverrideProvider.overrideWithValue(palette),
        appUiThemeClockProvider
            .overrideWithValue(clock ?? () => DateTime(2026, 10, 13, 12))
      ],
      child: ScreenUtilInit(
        designSize: const Size(360, 780),
        minTextAdapt: true,
        builder: (context, _) {
          ScreenUtil.configure(
              data: appContentMediaQuery(
                  MediaQueryData.fromView(View.of(context))),
              designSize: const Size(360, 780),
              minTextAdapt: true,
              splitScreenMode: true);
          return RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: palette != null
                    ? AppUiTheme.withPalette(AppTheme.lightTheme, palette)
                    : capture
                        ? AppTheme.lightTheme.copyWith(
                            textTheme: AppTheme.lightTheme.textTheme
                                .apply(fontFamily: family),
                            appBarTheme: AppTheme.lightTheme.appBarTheme
                                .copyWith(
                                    titleTextStyle: AppTheme
                                        .lightTheme.appBarTheme.titleTextStyle
                                        ?.copyWith(fontFamily: family)))
                        : AppTheme.lightTheme,
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(scale),
                        disableAnimations: reduceMotion),
                    child: AppContentFrame(child: child!)),
                home: const OnboardingScreen(),
              ));
        },
      )));
  await tester.pumpAndSettle();
  return AppLocalizations.of(tester.element(find.byType(OnboardingScreen)));
}

void main() {
  setUpAll(() async {
    if (capture && Platform.isWindows) {
      for (final entry in {
        'FeedbackLatin': 'arial.ttf',
        'FeedbackHindi': 'Nirmala.ttf',
        'FeedbackKorean': 'malgun.ttf'
      }.entries) {
        final bytes =
            await File('C:/Windows/Fonts/${entry.value}').readAsBytes();
        await (FontLoader(entry.key)
              ..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
      }
      final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
      await (FontLoader('MaterialIcons')..addFont(Future.value(icons))).load();
    }
  });

  for (final code in ['ko', 'en', 'de', 'pt', 'hi']) {
    testWidgets(
        '$code: folded onboarding shows each added shift and its irregular link',
        (tester) async {
      final key = GlobalKey();
      final l = await pumpOnboarding(
          tester, Locale(code), const Size(400, 632), 1, key);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(Dialog), findsNothing);
      await snapshot(tester, key, '${code}_names');
      if (capture) {
        await tester.ensureVisible(find.text(l.onboardingAddShiftName));
        await tester.tap(find.text(l.onboardingAddShiftName));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await snapshot(tester, key, code + '_name_input_keyboard');
        await tester.ensureVisible(find.text(l.commonCancel));
        await tester.tap(find.text(l.commonCancel));
        await tester.pumpAndSettle();
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text(l.onboardingNextPattern));
      await tester.pumpAndSettle();
      expect(find.text(l.onboardingNoPattern), findsNothing);
      expect(find.text(l.onboardingTodayPositionHint), findsNothing);
      await snapshot(tester, key, '${code}_pattern_empty');
      for (final name in [
        l.shiftDay,
        l.shiftNight,
        l.shiftDayOff,
        l.shiftDayOff
      ]) {
        final choice = find.descendant(of: _choices, matching: find.text(name));
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(
            find
                .descendant(of: _preview, matching: find.text(name))
                .last
                .hitTestable(),
            findsOneWidget);
      }
      await snapshot(tester, key, '${code}_pattern_added');
      if (capture) {
        await tester.ensureVisible(find.text(l.onboardingCompletePattern));
        await tester.tap(find.text(l.onboardingCompletePattern));
        await tester.pumpAndSettle();
        await tester
            .tap(find.byKey(const ValueKey('onboarding-pattern-slot-1')));
        await tester.pumpAndSettle();
        await snapshot(tester, key, code + '_today_selected');
        await tester.ensureVisible(find.text(l.onboardingEditPattern));
        await tester.tap(find.text(l.onboardingEditPattern));
        await tester.pumpAndSettle();
      }

      expect(tester.takeException(), isNull);
      // Removal operates on the preview, while the input remains available.
      await tester.tap(find.byKey(const ValueKey('onboarding-pattern-slot-1')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: _preview, matching: find.text(l.shiftNight)),
          findsNothing);
      await tester.ensureVisible(find.text(l.onboardingIrregularChoiceTitle));
      await tester.tap(find.text(l.onboardingIrregularChoiceTitle));
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      '40-day pattern remains visible at small size and large text; limit and back work',
      (tester) async {
    final key = GlobalKey();
    final l = await pumpOnboarding(
        tester, const Locale('de'), const Size(320, 568), 1.3, key);
    await tester.tap(find.text(l.onboardingNextPattern));
    await tester.pumpAndSettle();
    final choice =
        find.descendant(of: _choices, matching: find.text(l.shiftDay));
    for (var i = 0; i < 40; i++) {
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(
          find
              .descendant(of: _preview, matching: find.text(l.shiftDay))
              .last
              .hitTestable(),
          findsOneWidget);
    }
    final inputChip = tester.widget<AppUiShiftChip>(
        find.ancestor(of: choice, matching: find.byType(AppUiShiftChip)));
    expect(inputChip.enabled, isFalse);
    expect(find.byKey(const ValueKey('onboarding-pattern-slot-39')),
        findsOneWidget);
    expect(find.text('40 / 40'), findsNothing);
    await snapshot(tester, key, 'de_small_large_text_40_days');
    await tester.ensureVisible(find.text(l.onboardingCompletePattern));
    await tester.tap(find.text(l.onboardingCompletePattern));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
