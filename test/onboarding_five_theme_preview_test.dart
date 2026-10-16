import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/providers/app_ui_theme_preview_provider.dart';
import 'package:shiftbell/theme/app_ui_time_palettes.dart';
import 'package:shiftbell/widgets/alarm_time_editor.dart';
import 'package:shiftbell/screens/onboarding_screen.dart';
import 'package:shiftbell/widgets/app_ui_theme_preview.dart';
import 'onboarding_pattern_feedback_test.dart'
    show pumpOnboarding, snapshot, capture;

void main() {
  setUpAll(() async {
    if (capture && Platform.isWindows) {
      await (FontLoader('FeedbackKorean')
            ..addFont(Future.value(ByteData.sublistView(
                await File('C:/Windows/Fonts/malgun.ttf').readAsBytes()))))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(
                await rootBundle.load('fonts/MaterialIcons-Regular.otf'))))
          .load();
    }
  });
  test('local time boundaries cover the day including midnight', () {
    for (final pair in [
      (4, 59, AppUiTimeTheme.night),
      (5, 0, AppUiTimeTheme.dawn),
      (7, 59, AppUiTimeTheme.dawn),
      (8, 0, AppUiTimeTheme.morning),
      (10, 59, AppUiTimeTheme.morning),
      (11, 0, AppUiTimeTheme.daytime),
      (16, 59, AppUiTimeTheme.daytime),
      (17, 0, AppUiTimeTheme.evening),
      (20, 59, AppUiTimeTheme.evening),
      (21, 0, AppUiTimeTheme.night),
      (23, 59, AppUiTimeTheme.night),
      (0, 0, AppUiTimeTheme.night)
    ]) {
      expect(
          AppUiTimeTheme.forLocalTime(DateTime(2026, 10, 13, pair.$1, pair.$2)),
          pair.$3);
    }
  });
  test('every palette keeps text and selection guidance readable', () {
    double contrast(Color a, Color b) {
      final l = a.computeLuminance(), r = b.computeLuminance();
      return ((l > r ? l : r) + .05) / ((l > r ? r : l) + .05);
    }

    for (final theme in AppUiTimeTheme.values) {
      final p = theme.palette;
      expect(contrast(p.chipText, p.chipSurface), greaterThanOrEqualTo(4.5),
          reason: '${theme.name} chip name');
      expect(contrast(p.chipBorder, p.chipSurface), greaterThanOrEqualTo(3),
          reason: '${theme.name} chip boundary');
      expect(
          contrast(p.selectionOutline, p.chipSurface), greaterThanOrEqualTo(3),
          reason: '${theme.name} today boundary');
      expect(contrast(p.text, p.surface), greaterThanOrEqualTo(4.5),
          reason: '${theme.name} text');
      expect(contrast(p.secondaryText, p.background), greaterThanOrEqualTo(4.5),
          reason: '${theme.name} secondary');
      expect(contrast(p.primary, p.onPrimary), greaterThanOrEqualTo(4.5),
          reason: '${theme.name} button');
      expect(
          contrast(p.selectionOutline, p.background), greaterThanOrEqualTo(4.5),
          reason: '${theme.name} selection');
    }
  });
  test('rapid fixed choices and automatic mode survive new provider containers',
      () async {
    SharedPreferences.setMockInitialValues({});
    var container = ProviderContainer();
    await container.read(appUiThemePreviewProvider.future);
    final notifier = container.read(appUiThemePreviewProvider.notifier);
    await Future.wait([
      notifier.select(AppUiTimeTheme.evening),
      notifier.select(AppUiTimeTheme.dawn),
      notifier.select(AppUiTimeTheme.night)
    ]);
    container.dispose();
    container = ProviderContainer();
    expect(await container.read(appUiThemePreviewProvider.future),
        AppUiTimeTheme.night);
    await container.read(appUiThemePreviewProvider.notifier).select(null);
    container.dispose();
    container = ProviderContainer();
    expect(await container.read(appUiThemePreviewProvider.future), isNull);
    expect(
        (await SharedPreferences.getInstance())
            .getString(AppUiThemePreviewController.preferenceKey),
        'automatic');
    container.dispose();
  });
  testWidgets(
      'all saved palettes follow regular onboarding and its nested dialogs',
      (tester) async {
    final key = GlobalKey();
    final l = await pumpOnboarding(
        tester, const Locale('ko'), const Size(400, 800), 1, key);
    expect(find.byType(AppUiThemePreview), findsNothing);
    final controller =
        ProviderScope.containerOf(tester.element(find.byType(OnboardingScreen)))
            .read(appUiThemePreviewProvider.notifier);
    for (final theme in AppUiTimeTheme.values) {
      await controller.select(theme);
      await tester.pumpAndSettle();
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          theme.palette.background);
      await tester.pump(const Duration(milliseconds: 16));
      await snapshot(tester, key, 'theme_${theme.name}_names');
      await tester.tap(find.text(l.onboardingNextPattern));
      await tester.pumpAndSettle();
      if (theme == AppUiTimeTheme.dawn) {
        for (final name in [l.shiftDay, l.shiftNight]) {
          await tester.tap(find.descendant(
              of: find.byKey(const ValueKey('onboarding-shift-choices')),
              matching: find.text(name)));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text(l.onboardingCompletePattern));
        await tester.pumpAndSettle();
      }
      expect(
          tester
              .widget<Text>(find.text(l.onboardingTodayPositionHint))
              .style
              ?.color,
          theme.palette.selectionOutline);
      if (theme == AppUiTimeTheme.night) {
        await snapshot(tester, key, 'theme_night_today');
      }
      await tester.tap(find.byKey(const ValueKey('onboarding-pattern-slot-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.onboardingNextAlarms));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.onboardingEditAlarms).first);
      await tester.pumpAndSettle();
      expect(
          Theme.of(tester.element(find.byType(Dialog).last))
              .colorScheme
              .surface,
          theme.palette.surface);
      await tester.tap(find.text(l.alarmAdd));
      await tester.pumpAndSettle();
      expect(
          Theme.of(tester.element(find.byType(AlarmTimePicker)))
              .colorScheme
              .onSurface,
          theme.palette.text);
      if (theme == AppUiTimeTheme.night) {
        await snapshot(tester, key, 'theme_night_picker');
      }
      await tester.tap(find.text(l.commonCancel).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.commonCancel).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(
          (await SharedPreferences.getInstance())
              .getString(AppUiThemePreviewController.preferenceKey),
          theme.name);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpOnboarding(
        tester, const Locale('ko'), const Size(400, 800), 1, GlobalKey(),
        resetPreferences: false);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        AppUiTimeTheme.values.last.palette.background);
  });
  testWidgets(
      'automatic follows clock and resume while fixed mode ignores time',
      (tester) async {
    var now = DateTime(2026, 10, 13, 16, 59);
    await pumpOnboarding(
        tester, const Locale('ko'), const Size(400, 800), 1, GlobalKey(),
        clock: () => now);
    final controller =
        ProviderScope.containerOf(tester.element(find.byType(OnboardingScreen)))
            .read(appUiThemePreviewProvider.notifier);
    Color? background() =>
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor;
    expect(background(), AppUiTimeTheme.daytime.palette.background);
    now = DateTime(2026, 10, 13, 17);
    await tester.pump(AppUiTimeTheme.clockCheckInterval);
    await tester.pumpAndSettle();
    expect(background(), AppUiTimeTheme.evening.palette.background);
    await controller.select(AppUiTimeTheme.night);
    await tester.pumpAndSettle();
    now = DateTime(2026, 10, 14, 8);
    await tester.pump(AppUiTimeTheme.clockCheckInterval);
    await tester.pumpAndSettle();
    expect(background(), AppUiTimeTheme.night.palette.background);
    await controller.select(null);
    await tester.pumpAndSettle();
    expect(background(), AppUiTimeTheme.morning.palette.background);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = DateTime(2026, 10, 14, 12);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(background(), AppUiTimeTheme.daytime.palette.background);
    expect(tester.takeException(), isNull);
  });
}
