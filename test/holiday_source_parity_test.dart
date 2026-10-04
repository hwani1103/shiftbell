import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/utils/holiday_util.dart';

void main() {
  test('2026 공휴일 지정과 2027 월력요항: 시행 전 비소급 및 영어 숨김', () {
    HolidayOverrides.current = HolidayOverrides.empty;
    expect(getHolidayName(DateTime(2025, 1, 27), isKorean: true), '임시공휴일');
    expect(getHolidayName(DateTime(2025, 6, 3), isKorean: true), '대통령선거');
    expect(getHolidayName(DateTime(2028, 4, 12), isKorean: true), '국회의원선거');
    for (final year in [2026, 2027, 2028, 2029]) {
      expect(getHolidayName(DateTime(year, 5, 1), isKorean: true), '노동절');
      expect(getHolidayName(DateTime(year, 7, 17), isKorean: true), '제헌절');
      expect(getHolidayName(DateTime(year, 5, 1), isKorean: false), isNull);
    }
    expect(getHolidayName(DateTime(2025, 5, 1), isKorean: true), isNull);
    expect(getHolidayName(DateTime(2025, 7, 17), isKorean: true), isNull);
    expect(getHolidayName(DateTime(2027, 5, 3), isKorean: true), '대체공휴일');
    expect(getHolidayName(DateTime(2027, 7, 19), isKorean: true), '대체공휴일');
    expect(getHolidayName(DateTime(2027, 6, 7), isKorean: true), isNull);
    // KASA's 2027 announcement also revises the 2026 total after the two additions.
    for (final year in [2026, 2027]) {
      var redDays = 0;
      for (var day = DateTime(year); day.year == year; day = day.add(const Duration(days: 1))) {
        if (day.weekday == DateTime.sunday || getHolidayName(day, isKorean: true) != null) redDays++;
      }
      expect(redDays, 72, reason: '$year official red-calendar-day total');
    }
  });
  test('앱·웹 공용 공휴일 날짜와 Android 위젯 날짜가 일치한다', () {
    final source = File(
      'android/app/src/main/kotlin/com/hwani1103/shiftbell/CalendarWidgetHolidays.kt',
    ).readAsStringSync();
    final fixedBlock = RegExp(
      r'FIXED_HOLIDAYS\s*=\s*setOf\((.*?)\)',
      dotAll: true,
    ).firstMatch(source);
    final annualBlock = RegExp(
      r'LUNAR_HOLIDAYS\s*=\s*setOf\((.*?)\)',
      dotAll: true,
    ).firstMatch(source);

    expect(fixedBlock, isNotNull);
    expect(annualBlock, isNotNull);

    final nativeFixed = RegExp(r'"(\d{2}-\d{2})"')
        .allMatches(fixedBlock!.group(1)!)
        .map((match) => match.group(1)!)
        .toSet();
    final nativeAnnual = RegExp(r'"(\d{4}-\d{2}-\d{2})"')
        .allMatches(annualBlock!.group(1)!)
        .map((match) => match.group(1)!)
        .toSet();

    expect(nativeFixed, fixedHolidays.keys.toSet());
    expect(nativeAnnual, lunarHolidays.keys.toSet());
  });
}
