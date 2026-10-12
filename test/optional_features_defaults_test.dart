import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/providers/tab_visibility_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final existing in [false, true]) {
    test('missing choices: existing=$existing', () async {
      SharedPreferences.setMockInitialValues({});
      await initializeTabVisibilityDefaults(hasExistingSchedule: existing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('schedule_tab_enabled'), existing);
      expect(prefs.getBool('condition_tab_enabled'), existing);
      await initializeTabVisibilityDefaults(hasExistingSchedule: !existing);
      expect(prefs.getBool('schedule_tab_enabled'), existing);
      expect(prefs.getBool('condition_tab_enabled'), existing);
    });
    for (final visible in [false, true]) {
      test('stored/restored choice $visible survives existing=$existing',
          () async {
        SharedPreferences.setMockInitialValues({
          'schedule_tab_enabled': visible,
          'condition_tab_enabled': !visible,
        });
        await initializeTabVisibilityDefaults(hasExistingSchedule: existing);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('schedule_tab_enabled'), visible);
        expect(prefs.getBool('condition_tab_enabled'), !visible);
      });
    }
  }
  test('existing user who reset their schedule keeps the old visible default',
      () async {
    SharedPreferences.setMockInitialValues({'permissions_requested': true});
    await initializeTabVisibilityDefaults(hasExistingSchedule: false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('schedule_tab_enabled'), true);
    expect(prefs.getBool('condition_tab_enabled'), true);
  });
}
