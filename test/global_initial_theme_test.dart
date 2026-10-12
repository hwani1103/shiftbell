import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/calendar_theme.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/providers/calendar_theme_provider.dart';
import 'package:shiftbell/utils/shift_name_util.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  for (final code in ['ko', 'en', 'de', 'pt', 'hi', 'fr']) {
    test('Fresh $code install loads the locale default before its first frame',
        () async {
      binding.platformDispatcher.localesTestValue = [Locale(code)];
      addTearDown(binding.platformDispatcher.clearLocalesTestValue);
      SharedPreferences.setMockInitialValues({});
      final expected =
          code == 'ko' ? CalendarThemeId.mainWhite : CalendarThemeId.periwinkle;
      expect(await CalendarThemeNotifier.loadInitial(), expected);
      final container = ProviderContainer();
      expect(container.read(calendarThemeProvider), expected);
      container.dispose();
    });
  }

  test('An existing selected theme is preserved across language changes',
      () async {
    for (final code in ['ko', 'en', 'de', 'pt', 'hi']) {
      binding.platformDispatcher.localesTestValue = [Locale(code)];
      addTearDown(binding.platformDispatcher.clearLocalesTestValue);
      for (final theme in CalendarThemeId.values) {
        SharedPreferences.setMockInitialValues(
            {'calendar_theme_id': theme.name});
        expect(await CalendarThemeNotifier.loadInitial(), theme);
      }
    }
  });

  test(
      'Every initial Periwinkle colour keeps readable text on the joined label',
      () {
    for (final color in kPeriwinklePalette) {
      final ink = ShiftSchedule.getTextColor(color);
      final a = ink.computeLuminance(), b = color.computeLuminance();
      final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: color.toARGB32().toRadixString(16));
    }
  });

  test(
      'Global defaults are valid compact names and classify only time off as rest',
      () {
    for (final code in ['en', 'de', 'pt', 'hi']) {
      final l = lookupAppLocalizations(Locale(code));
      final names = [
        l.shiftDay,
        l.shiftNight,
        l.shiftMorning,
        l.shiftAfternoon,
        l.shiftDayOff,
        l.shiftAnnualLeave
      ];
      expect(names.toSet(), hasLength(6));
      for (var i = 0; i < names.length; i++) {
        expect(validateShiftName(names[i]), isNull,
            reason: '$code ${names[i]}');
        expect(names[i].characters.length, lessThanOrEqualTo(8));
        expect(isRestShiftName(names[i]), i >= 4, reason: '$code ${names[i]}');
      }
      final colors =
          effectiveShiftColors(names, CalendarThemeId.periwinkle, null);
      expect(colors[l.shiftDayOff], kPeriwinkleRestColor);
      expect(colors[l.shiftAnnualLeave], kPeriwinkleRestColor);
      expect(names.take(4).map((n) => colors[n]).toSet(), hasLength(4));
      expect(colors.values, isNot(contains(kMainRestColor)));
      final custom = effectiveShiftColors(names, CalendarThemeId.periwinkle,
          {l.shiftDay: Colors.orange.toARGB32()});
      expect(custom[l.shiftDay]!.toARGB32(), Colors.orange.toARGB32());
    }
    for (final name in ['All day', 'URL support', 'Ferry', 'Early', 'Late']) {
      expect(isRestShiftName(name), isFalse, reason: name);
    }
  });
}
