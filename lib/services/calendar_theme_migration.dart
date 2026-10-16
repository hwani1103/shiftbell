import 'package:shared_preferences/shared_preferences.dart';

/// One-time appearance upgrade. Existing designs keep their identity; only
/// the two former main designs merge. New installs alone default to automatic.
abstract final class CalendarThemeMigration {
  static const themeKey = 'calendar_theme_id';
  static const paletteKey = 'app_ui_preview_theme';
  static const completedKey = 'calendar_main_merge_v1';
  static const previousKey = 'calendar_main_before_merge';
  static const appearanceCompletedKey = 'screen_palette_migration_v2';
  static const explicitChoiceKey = 'screen_palette_user_selected';
  static Future<void>? _queue;

  /// Also used on a failed write so an upgrade never flashes automatic colors.
  static String initialPalette(SharedPreferences prefs) {
    final saved = prefs.getString(paletteKey);
    if (prefs.getString(themeKey) == 'mainDark') return 'night';
    if (saved == 'originalDark') return 'night';
    if (prefs.getBool(appearanceCompletedKey) == true ||
        prefs.getBool(explicitChoiceKey) == true) {
      return saved ?? 'automatic';
    }
    final previous = prefs.getString(previousKey);
    // Fixed choices already made in the earlier screen-color selector survive.
    if (saved != null && saved != 'automatic') return saved;
    // V1 pinned main users first, so automatic saved after its completion was
    // a deliberate later selection, not the old default.
    if (prefs.getBool(completedKey) == true &&
        previous != null &&
        saved == 'automatic') {
      return 'automatic';
    }
    if (previous == 'mainDark') return 'night';
    final existing = prefs.containsKey(themeKey) ||
        previous != null ||
        prefs.getBool('permissions_requested') == true ||
        prefs.getBool('welcome_popup_shown') == true;
    return existing ? 'originalWhite' : 'automatic';
  }

  static Future<void> apply(SharedPreferences prefs, {String? defaultTheme}) {
    // Both startup providers may request migration; serialize their writes.
    final operation = (_queue ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) async {
      final current = prefs.getString(themeKey);
      if (prefs.getBool(appearanceCompletedKey) == true &&
          current != 'mainDark' &&
          prefs.getString(paletteKey) != 'originalDark') {
        return;
      }
      final selected = initialPalette(prefs);
      final existing = current != null ||
          prefs.getBool('permissions_requested') == true ||
          prefs.getBool('welcome_popup_shown') == true;
      final source = current == 'mainDark'
          ? current
          : prefs.getString(previousKey) ??
              (existing ? current ?? defaultTheme : null);
      Future<void> checked(Future<bool> write) async {
        if (!await write) {
          throw StateError('Calendar appearance migration failed');
        }
      }

      if (source == 'mainWhite' || source == 'mainDark') {
        await checked(prefs.setString(previousKey, source!));
        // Preserve another design selected after an older completed migration.
        if (current == null ||
            current == 'mainWhite' ||
            current == 'mainDark') {
          await checked(prefs.setString(themeKey, 'mainWhite'));
        }
      }
      await checked(prefs.setString(paletteKey, selected));
      await checked(prefs.setBool(completedKey, true));
      // Last write: retries are safe after partial persistence.
      await checked(prefs.setBool(appearanceCompletedKey, true));
    });
    _queue = operation;
    return operation.whenComplete(() {
      if (identical(_queue, operation)) _queue = null;
    });
  }
}
