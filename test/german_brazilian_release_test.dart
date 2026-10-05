import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/constants/shift_name_limits.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/l10n/release_locale.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/utils/shift_name_util.dart';

void main() {
  Map<String, dynamic> arb(String language) =>
      jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync());
  final source = arb('en');
  for (final language in ['de', 'pt']) {
    final translated = arb(language);
    test('$language covers all messages and preserves interpolation', () {
      final arguments = RegExp(r'\{(\w+)[},]');
      Set<String> args(String value) => arguments.allMatches(value).map((m) => m[1]!).toSet();
      for (final key in source.keys.where((key) => !key.startsWith('@'))) {
        expect(translated.containsKey(key), isTrue, reason: key);
        final value = translated[key] as String;
        expect(value.trim(), isNotEmpty, reason: key);
        expect(args(value), args(source[key]), reason: key);
        expect(RegExp('[가-힣]').hasMatch(value), isFalse, reason: key);
      }
    });
    test('$language defaults are short and recognized as work or rest', () {
      for (final key in ['shiftDay', 'shiftNight', 'shiftMorning', 'shiftAfternoon', 'shiftDayOff', 'shiftAnnualLeave']) {
        final value = translated[key] as String;
        expect(value.length, lessThanOrEqualTo(6), reason: key);
        expect(validateShiftName(value), isNull, reason: key);
        expect(isRestShiftName(value), ['shiftDayOff', 'shiftAnnualLeave'].contains(key), reason: key);
      }
      expect(shiftNameLengthLimit('WWWWWWWWWWWWWWWW'), 16);
      expect(validateShiftName('WWWWWWWWWWWWWWWW'), isNull);
      expect(validateShiftName('WWWWWWWWWWWWWWWWW'), ShiftNameIssue.tooLong);
      expect(shiftNameLengthLimit('Frühschicht'), 16);
      expect(shiftNameLengthLimit('Plantão'), 16);
    });
  }
  test('only Korean privacy contact keeps Korean contact channels', () {
    for (final language in ['en', 'de', 'pt']) {
      final contact = arb(language)['privacyContactBody'] as String;
      expect(contact, contains('lowvibe07@gmail.com'));
      expect(contact.toLowerCase(), isNot(contains('tistory')));
      expect(contact.toLowerCase(), isNot(contains('kakao')));
    }
    expect(arb('ko')['privacyContactBody'], contains('tistory'));
  });
  test('German and Brazilian locale selection and actual delegates', () async {
    const supported = [Locale('ko'), Locale('en', 'US'), Locale('en', 'GB'), Locale('de', 'DE'), Locale('pt', 'BR')];
    expect(resolveReleaseLocale([const Locale('de', 'DE')], supported), const Locale('de', 'DE'));
    expect(resolveReleaseLocale([const Locale('pt', 'BR')], supported), const Locale('pt', 'BR'));
    expect(resolveReleaseLocale([const Locale('de')], supported), const Locale('de', 'DE'));
    final de = await AppLocalizations.delegate.load(const Locale('de', 'DE'));
    final pt = await AppLocalizations.delegate.load(const Locale('pt', 'BR'));
    expect(de.shiftMorning, 'Früh');
    expect(pt.shiftAnnualLeave, 'Férias');
    expect(de.alarmRemainingDays(2), '2 Tage');
    expect(pt.alarmRemainingHours(2), '2 horas');
    expect(de.teamEditSwitchConfirm('A', 'B'), contains('Team B'));
    expect(pt.teamEditSwitchConfirm('A', 'B'), contains('equipe B'));
  });
}
