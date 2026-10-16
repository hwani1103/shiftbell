import '../theme/app_ui_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_ui_time_palettes.dart';
import '../services/calendar_theme_migration.dart';

class AppUiThemePreviewController extends AsyncNotifier<AppUiTimeTheme?> {
  static const preferenceKey = 'app_ui_preview_theme';
  Future<void> _saveQueue = Future<void>.value();
  @override
  Future<AppUiTimeTheme?> build() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String saved;
      try {
        await CalendarThemeMigration.apply(prefs);
        saved = prefs.getString(preferenceKey) ?? 'automatic';
      } catch (_) {
        saved = CalendarThemeMigration.initialPalette(prefs);
      }
      for (final theme in AppUiTimeTheme.values) {
        if (theme.name == saved) return theme;
      }
    } catch (_) {
      debugPrint('UI preview preference unavailable; using default palette.');
    }
    return null;
  }

  Future<void> select(AppUiTimeTheme? theme) {
    state = AsyncData(theme);
    // Serialize rapid taps so an older write cannot overwrite the latest choice.
    _saveQueue = _saveQueue.catchError((Object _) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final saved =
          await prefs.setString(preferenceKey, theme?.name ?? 'automatic');
      if (!saved) throw StateError('UI preview preference was not saved');
      if (!await prefs.setBool(
          CalendarThemeMigration.explicitChoiceKey, true)) {
        throw StateError('UI preview selection marker was not saved');
      }
    });
    return _saveQueue;
  }
}

final appUiThemePreviewProvider =
    AsyncNotifierProvider<AppUiThemePreviewController, AppUiTimeTheme?>(
        AppUiThemePreviewController.new);

final appUiThemeClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// Optional upper-level palette injection for design verification or future themes.
final appUiThemePaletteOverrideProvider =
    Provider<AppUiPalette?>((ref) => null);
