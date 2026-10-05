import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/l10n/release_locale.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/utils/shift_name_util.dart';
import 'package:shiftbell/widgets/shift_name_text_field.dart';

void main() {
  final source = jsonDecode(File('lib/l10n/app_ko.arb').readAsStringSync())
      as Map<String, dynamic>;
  final hi = jsonDecode(File('lib/l10n/app_hi.arb').readAsStringSync())
      as Map<String, dynamic>;

  test('Hindi covers the source and preserves all interpolation arguments', () {
    final keys = source.keys.where((k) => !k.startsWith('@')).toSet();
    expect(hi.keys.where((k) => !k.startsWith('@')).toSet(), keys);
    Set<String> args(String text) => RegExp(r'\{(\w+)[},]')
        .allMatches(text).map((m) => m[1]!).toSet();
    for (final key in keys) {
      final value = hi[key] as String;
      expect(value.trim(), isNotEmpty, reason: key);
      expect(args(value), args(source[key]), reason: key);
      expect(RegExp('[가-힣]').hasMatch(value), isFalse, reason: key);
    }
    expect(hi['privacyContactBody'],
        'ऐप में मदद या निजता से जुड़े सवालों के लिए:\nlowvibe07@gmail.com');
  });

  test('Hindi locale and generated plural messages load correctly', () async {
    expect(resolveReleaseLocale([const Locale('hi')], AppLocalizations.supportedLocales),
        const Locale('hi', 'IN'));
    final l10n = await AppLocalizations.delegate.load(const Locale('hi', 'IN'));
    expect(l10n.alarmRemainingHours(1), '1 घंटा');
    expect(l10n.alarmRemainingHours(2), '2 घंटे');
    expect(l10n.alarmRemainingHoursMinutes(2, 30), '2 घंटे 30 मिनट');
    expect(l10n.teamEditSwitchConfirm('A', 'B'), contains('टीम B'));
    expect(l10n.onboardingSwitchToIrregularPrefix +
        l10n.onboardingSwitchToIrregularLink + l10n.onboardingSwitchToIrregularSuffix,
        'शिफ्ट का तय क्रम नहीं है? यहां टैप करें।');
  });

  test('Hindi defaults remain short and distinguish work from rest', () {
    for (final key in ['shiftDay', 'shiftNight', 'shiftMorning',
      'shiftAfternoon', 'shiftDayOff', 'shiftAnnualLeave']) {
      final name = hi[key] as String;
      expect(name.characters.length, lessThanOrEqualTo(6));
      expect(validateShiftName(name), isNull);
      expect(isRestShiftName(name), ['shiftDayOff', 'shiftAnnualLeave'].contains(key));
    }
    expect(isRestShiftName('अवकाशप्राप्त'), isFalse);
    expect(isRestShiftName('रात की शिफ्ट'), isFalse);
    // A Devanagari matra stays with its base character at the existing limit.
    final name = List.filled(16, 'ना').join();
    expect(validateShiftName(name), isNull);
    expect(validateShiftName('$name ना'), ShiftNameIssue.tooLong);
    final formatted = ShiftNameLengthFormatter().formatEditUpdate(
        TextEditingValue.empty, TextEditingValue(text: '${name}ना'));
    expect(formatted.text, name);
  });
}
