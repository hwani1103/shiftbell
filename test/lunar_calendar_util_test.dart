// test/lunar_calendar_util_test.dart
//
// lunar_calendar_data.dart의 사전 계산 표가 실제 KASI 기준 음력과 맞는지 확인.
// 검증 기준값은 holiday_util.dart의 lunarHolidays(설날=음력 1.1, 추석=음력 8.15가
// 가운데 날짜)와 korean_lunar_calendar(PyPI, KASI 데이터 기반) 패키지로 직접 계산한
// 값을 같이 씀 - 표를 다시 뽑을 때(연도 확장 등) 이 테스트가 회귀를 잡아줌.

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/utils/lunar_calendar_util.dart';

void main() {
  group('solarToLunar', () {
    test('설날(음력 1.1) - 2025-01-29', () {
      final lunar = solarToLunar(DateTime(2025, 1, 29));
      expect(lunar, isNotNull);
      expect(lunar!.month, 1);
      expect(lunar.day, 1);
      expect(lunar.isLeapMonth, false);
    });

    test('추석(음력 8.15) - 2026-09-25', () {
      final lunar = solarToLunar(DateTime(2026, 9, 25));
      expect(lunar, isNotNull);
      expect(lunar!.month, 8);
      expect(lunar.day, 15);
    });

    test('설날(음력 1.1) - 2024-02-10', () {
      final lunar = solarToLunar(DateTime(2024, 2, 10));
      expect(lunar, isNotNull);
      expect(lunar!.month, 1);
      expect(lunar.day, 1);
    });

    test('윤달 - 2017-06-24 (음력 윤5.1)', () {
      final lunar = solarToLunar(DateTime(2017, 6, 24));
      expect(lunar, isNotNull);
      expect(lunar!.month, 5);
      expect(lunar.day, 1);
      expect(lunar.isLeapMonth, true);
    });

    test('설날(음력 1.1) - 2027-02-07', () {
      final lunar = solarToLunar(DateTime(2027, 2, 7));
      expect(lunar, isNotNull);
      expect(lunar!.month, 1);
      expect(lunar.day, 1);
    });

    test('설날(음력 1.1) - 2029-02-13 (설날 가운데 날짜)', () {
      final lunar = solarToLunar(DateTime(2029, 2, 13));
      expect(lunar, isNotNull);
      expect(lunar!.month, 1);
      expect(lunar.day, 1);
    });

    test('표 범위 밖(과거)이면 null', () {
      expect(solarToLunar(DateTime(2000, 1, 1)), isNull);
    });

    test('표 범위 밖(미래)이면 null', () {
      expect(solarToLunar(DateTime(2050, 1, 1)), isNull);
    });

    test('연속된 날짜는 하루씩 증가(월 경계 포함)', () {
      final d1 = solarToLunar(DateTime(2025, 1, 28)); // 음력 12.29 (섣달 그믐)
      final d2 = solarToLunar(DateTime(2025, 1, 29)); // 음력 1.1
      expect(d1, isNotNull);
      expect(d2, isNotNull);
      expect(d1!.month, 12);
      expect(d2!.month, 1);
      expect(d2.day, 1);
    });
  });

  group('formatLunarDate', () {
    test('평달 - 상세팝업용', () {
      final lunar = LunarDate(month: 4, day: 14, isLeapMonth: false);
      expect(formatLunarDateFull(lunar), '음력 4.14');
    });

    test('윤달 - 상세팝업용', () {
      final lunar = LunarDate(month: 4, day: 14, isLeapMonth: true);
      expect(formatLunarDateFull(lunar), '음력 윤4.14');
    });

    test('평달 - 메인 달력 셀용', () {
      final lunar = LunarDate(month: 4, day: 14, isLeapMonth: false);
      expect(formatLunarDateCompact(lunar), '(4.14)');
    });

    test('윤달 - 메인 달력 셀용', () {
      final lunar = LunarDate(month: 4, day: 14, isLeapMonth: true);
      expect(formatLunarDateCompact(lunar), '(윤4.14)');
    });
  });
}
