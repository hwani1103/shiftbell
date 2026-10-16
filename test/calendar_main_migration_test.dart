import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/models/calendar_theme.dart';
import 'package:shiftbell/providers/calendar_theme_provider.dart';
import 'package:shiftbell/providers/app_ui_theme_preview_provider.dart';
import 'package:shiftbell/services/calendar_theme_migration.dart';
import 'package:shiftbell/theme/app_ui_time_palettes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final old in CalendarThemeId.values) {
    test('legacy ${old.name} starts fixed and keeps its calendar design',
        () async {
      SharedPreferences.setMockInitialValues({'calendar_theme_id': old.name});
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        CalendarThemeMigration.apply(prefs),
        CalendarThemeMigration.apply(prefs),
      ]);
      expect(
          prefs.getString(CalendarThemeMigration.themeKey), old.canonical.name);
      expect(prefs.getString(CalendarThemeMigration.paletteKey),
          old == CalendarThemeId.mainDark ? 'night' : 'originalWhite');
      final c = ProviderContainer();
      await c.read(appUiThemePreviewProvider.future);
      await c.read(appUiThemePreviewProvider.notifier).select(null);
      c.dispose();
      await CalendarThemeMigration.apply(prefs);
      expect(prefs.getString(CalendarThemeMigration.paletteKey), 'automatic');
    });
  }
  test('new install stays automatic after onboarding writes legacy flags',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await CalendarThemeMigration.apply(prefs);
    expect(prefs.getString(CalendarThemeMigration.paletteKey), 'automatic');
    await prefs.setBool('permissions_requested', true);
    await prefs.setBool('welcome_popup_shown', true);
    await prefs.setString(CalendarThemeMigration.themeKey, 'diary');
    await CalendarThemeMigration.apply(prefs);
    expect(prefs.getString(CalendarThemeMigration.paletteKey), 'automatic');
    expect(prefs.getString(CalendarThemeMigration.themeKey), 'diary');
  });
  test('V1 upgrade consolidates dark and fixes other legacy defaults',
      () async {
    for (final saved in ['originalDark', 'automatic']) {
      SharedPreferences.setMockInitialValues({
        CalendarThemeMigration.completedKey: true,
        CalendarThemeMigration.themeKey: 'diary',
        CalendarThemeMigration.paletteKey: saved,
      });
      final prefs = await SharedPreferences.getInstance();
      await CalendarThemeMigration.apply(prefs);
      expect(prefs.getString(CalendarThemeMigration.paletteKey),
          saved == 'originalDark' ? 'night' : 'originalWhite');
      expect(prefs.getString(CalendarThemeMigration.themeKey), 'diary');
    }
  });
  test('manual automatic chosen after V1 main merge survives V2', () async {
    SharedPreferences.setMockInitialValues({
      CalendarThemeMigration.completedKey: true,
      CalendarThemeMigration.previousKey: 'mainDark',
      CalendarThemeMigration.themeKey: 'diary',
      CalendarThemeMigration.paletteKey: 'automatic',
    });
    final prefs = await SharedPreferences.getInstance();
    await CalendarThemeMigration.apply(prefs);
    expect(prefs.getString(CalendarThemeMigration.paletteKey), 'automatic');
    expect(prefs.getString(CalendarThemeMigration.themeKey), 'diary');
  });
  for (final old in ['mainWhite', 'mainDark']) {
    test(
        'upgrade ' +
            old +
            ' archives choice and pins its existing brightness once', () async {
      SharedPreferences.setMockInitialValues({
        'calendar_theme_id': old,
        'app_ui_preview_theme': 'automatic',
        'unrelated': 'keep'
      });
      expect(
          await CalendarThemeNotifier.loadInitial(), CalendarThemeId.mainWhite);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(CalendarThemeMigration.previousKey), old);
      expect(prefs.getString('calendar_theme_id'), 'mainWhite');
      expect(prefs.getString('app_ui_preview_theme'),
          old == 'mainDark' ? 'night' : 'originalWhite');
      var c = ProviderContainer();
      expect(
          await c.read(appUiThemePreviewProvider.future),
          old == 'mainDark'
              ? AppUiTimeTheme.night
              : AppUiTimeTheme.originalWhite);
      await c.read(appUiThemePreviewProvider.notifier).select(null);
      c.dispose();
      expect(
          await CalendarThemeNotifier.loadInitial(), CalendarThemeId.mainWhite);
      c = ProviderContainer();
      expect(await c.read(appUiThemePreviewProvider.future), isNull);
      c.dispose();
      expect(prefs.getString('unrelated'), 'keep');
    });
  }
  test('interrupted dark migration resumes from archived selection', () async {
    SharedPreferences.setMockInitialValues({
      'calendar_theme_id': 'mainWhite',
      CalendarThemeMigration.previousKey: 'mainDark',
      'app_ui_preview_theme': 'originalDark'
    });
    final prefs = await SharedPreferences.getInstance();
    await CalendarThemeMigration.apply(prefs);
    expect(prefs.getString('app_ui_preview_theme'), 'night');
    expect(prefs.getBool(CalendarThemeMigration.completedKey), true);
  });
  test('fresh install retains automatic and other designs keep their choice',
      () async {
    for (final theme in [null, 'diary', 'periwinkle', 'softMosaic']) {
      SharedPreferences.setMockInitialValues({
        if (theme != null) 'calendar_theme_id': theme,
        'app_ui_preview_theme': 'morning'
      });
      final prefs = await SharedPreferences.getInstance();
      await CalendarThemeMigration.apply(prefs);
      expect(prefs.getString('app_ui_preview_theme'), 'morning');
      expect(prefs.getString(CalendarThemeMigration.previousKey), isNull);
    }
  });
  test('old default Korean main without explicit ID becomes fixed white',
      () async {
    SharedPreferences.setMockInitialValues({'permissions_requested': true});
    final prefs = await SharedPreferences.getInstance();
    await CalendarThemeMigration.apply(prefs);
    expect(prefs.getString('app_ui_preview_theme'), 'originalWhite');
  });
  test('old overseas default without explicit ID is not reclassified as main',
      () async {
    SharedPreferences.setMockInitialValues({'permissions_requested': true});
    final prefs = await SharedPreferences.getInstance();
    await CalendarThemeMigration.apply(prefs, defaultTheme: 'periwinkle');
    expect(prefs.getString('app_ui_preview_theme'), 'originalWhite');
  });
  test('legacy dark restored after completion still migrates as dark',
      () async {
    SharedPreferences.setMockInitialValues({
      'calendar_theme_id': 'mainDark',
      CalendarThemeMigration.completedKey: true,
      CalendarThemeMigration.previousKey: 'mainWhite'
    });
    final prefs = await SharedPreferences.getInstance();
    await CalendarThemeMigration.apply(prefs);
    expect(prefs.getString('app_ui_preview_theme'), 'night');
  });
  test('picker order and available choices contain one main design', () {
    expect(kAllCalendarThemeIds, [
      CalendarThemeId.mainWhite,
      CalendarThemeId.minimal,
      CalendarThemeId.materialCard,
      CalendarThemeId.boldGrid,
      CalendarThemeId.eventChip,
      CalendarThemeId.diary,
      CalendarThemeId.initialBadge,
      CalendarThemeId.underline,
      CalendarThemeId.editorial
    ]);
    expect(
        kEnglishCalendarThemeIds,
        containsAll([
          CalendarThemeId.periwinkle,
          CalendarThemeId.softMosaic,
          CalendarThemeId.mainWhite
        ]));
    expect(kEnglishCalendarThemeIds, isNot(contains(CalendarThemeId.mainDark)));
  });
  test('merged main preserves saved dark shift colours and custom overrides',
      () {
    final saved = {'주간': 0xff778899, '야간': 0xff112233};
    final colors =
        mainCalendarShiftColors(['주간', '야간', '휴무'], saved, {'야간': 0xffaabbcc});
    expect(colors['주간']!.toARGB32(), 0xff778899);
    expect(colors['야간']!.toARGB32(), 0xffaabbcc);
    expect(colors['휴무'], isNotNull);
    expect(saved['야간'], 0xff112233);
  });
}
