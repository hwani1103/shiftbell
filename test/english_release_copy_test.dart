import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/constants/shift_name_limits.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/utils/shift_name_util.dart';

void main() {
  final ko = jsonDecode(File('lib/l10n/app_ko.arb').readAsStringSync())
      as Map<String, dynamic>;
  final en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
      as Map<String, dynamic>;
  test('English messages cover every Korean key and preserve ICU arguments',
      () {
    final arguments = RegExp(r'\{(\w+)[},]');
    for (final key in ko.keys.where((key) => !key.startsWith('@'))) {
      expect(en.containsKey(key), isTrue, reason: key);
      expect(RegExp('[가-힣]').hasMatch(en[key] as String), isFalse, reason: key);
      Set<String> args(String value) =>
          arguments.allMatches(value).map((m) => m[1]!).toSet();
      expect(args(en[key] as String), args(ko[key] as String), reason: key);
    }
  });
  test(
      'English onboarding defaults satisfy the same shift-name validation as edits',
      () {
    for (final key in [
      'shiftDay',
      'shiftNight',
      'shiftMorning',
      'shiftAfternoon',
      'shiftDayOff',
      'shiftAnnualLeave'
    ]) {
      final value = en[key] as String;
      expect(value.length, lessThanOrEqualTo(kMaxShiftNameLength));
      expect(validateShiftName(value), isNull);
    }
  });
  test('English rest names do not mistake Office or Forestry for time off', () {
    for (final name in [
      'Off',
      'Day Off',
      'Leave',
      'Paid Leave',
      'Vacation',
      'PTO',
      '휴무'
    ]) {
      expect(isRestShiftName(name), isTrue, reason: name);
    }
    for (final name in [
      'Office',
      'Officer',
      'Forestry',
      'Afternoon',
      'Night duty'
    ]) {
      expect(isRestShiftName(name), isFalse, reason: name);
    }
  });
}
