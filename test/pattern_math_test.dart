// 순수 로직 검증: 패턴 계산이 1년 내내(연도 경계/윤년 포함) 정확히 도는지.
// 기기/시간조작 전혀 필요 없음 - 실제 앱이 쓰는 ShiftSchedule 클래스를 그대로 씀.
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';

void main() {
  group('패턴 계산 1년치 정확성 검증', () {
    test('4교대 패턴이 366일 내내 정확히 순환한다', () {
      final pattern = ['주', '주', '야', '야', '비', '비', '휴'];
      final schedule = ShiftSchedule(
        isRegular: true,
        pattern: pattern,
        todayIndex: 0,
        shiftTypes: pattern,
        startDate: DateTime(2026, 1, 1),
      );

      final start = DateTime(2026, 1, 1);
      for (int i = 0; i < 366; i++) {
        final date = start.add(Duration(days: i));
        final shift = schedule.getShiftForDate(date);
        expect(pattern.contains(shift), true, reason: '$date -> "$shift" 가 패턴 목록에 없음');
        expect(shift, pattern[i % pattern.length], reason: '$date (i=$i) 인덱스 불일치');
      }
    });

    test('연도 경계(12/31→1/1)를 넘어가도 안 깨진다', () {
      final pattern = ['A', 'B', 'C'];
      final schedule = ShiftSchedule(
        isRegular: true,
        pattern: pattern,
        todayIndex: 1,
        shiftTypes: pattern,
        startDate: DateTime(2026, 12, 25),
      );
      for (int i = -10; i <= 20; i++) {
        final date = DateTime(2026, 12, 31).add(Duration(days: i));
        expect(() => schedule.getShiftForDate(date), returnsNormally);
      }
    });

    test('윤년 2/29을 포함해도 정상 동작한다 (2028년)', () {
      final pattern = ['A', 'B'];
      final schedule = ShiftSchedule(
        isRegular: true,
        pattern: pattern,
        todayIndex: 0,
        shiftTypes: pattern,
        startDate: DateTime(2028, 1, 1),
      );
      final feb29 = DateTime(2028, 2, 29);
      expect(() => schedule.getShiftForDate(feb29), returnsNormally);

      final mar1 = DateTime(2028, 3, 1);
      final daysDiff = mar1.difference(DateTime(2028, 1, 1)).inDays;
      expect(schedule.getShiftForDate(mar1), pattern[daysDiff % pattern.length]);
    });

    test('assignedDates 예외가 패턴보다 우선 적용된다 (10일치 윈도우 밖 날짜에도)', () {
      final pattern = ['A', 'B'];
      final farDate = DateTime.now().add(Duration(days: 100));
      final dateKey = farDate.toIso8601String().split('T')[0];
      final schedule = ShiftSchedule(
        isRegular: true,
        pattern: pattern,
        todayIndex: 0,
        shiftTypes: pattern,
        startDate: DateTime.now(),
        assignedDates: {dateKey: '특별근무'},
      );
      expect(schedule.getShiftForDate(farDate), '특별근무');
    });

    test('패턴 길이가 1이어도(매일 같은 근무) 안 깨진다', () {
      final pattern = ['매일근무'];
      final schedule = ShiftSchedule(
        isRegular: true,
        pattern: pattern,
        todayIndex: 0,
        shiftTypes: pattern,
        startDate: DateTime(2026, 1, 1),
      );
      for (int i = 0; i < 365; i++) {
        expect(
          schedule.getShiftForDate(DateTime(2026, 1, 1).add(Duration(days: i))),
          '매일근무',
        );
      }
    });

    test('음수 today_index / 음수 daysDiff도 안전하게 처리된다', () {
      final pattern = ['X', 'Y', 'Z'];
      final schedule = ShiftSchedule(
        isRegular: true,
        pattern: pattern,
        todayIndex: -1, // 비정상 값이어도 크래시는 안 나야 함
        shiftTypes: pattern,
        startDate: DateTime(2026, 6, 15),
      );
      // startDate보다 과거 날짜(음수 daysDiff)도 테스트
      for (int i = -30; i < 30; i++) {
        final date = DateTime(2026, 6, 15).add(Duration(days: i));
        expect(() => schedule.getShiftForDate(date), returnsNormally);
        expect(pattern.contains(schedule.getShiftForDate(date)), true);
      }
    });
  });
}
