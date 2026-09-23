// 1.0.24 D - 공휴일 원격 변경분: 병합 우선순위와 잘못된 입력 방어.
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/utils/holiday_util.dart';

void main() {
  tearDown(() => HolidayOverrides.current = HolidayOverrides.empty);

  test('원격 값이 없으면 기존 하드코딩 목록 그대로', () {
    expect(getHolidayName(DateTime(2026, 9, 24), isKorean: true), '추석');
    expect(getHolidayName(DateTime(2026, 3, 1), isKorean: true), '삼일절');
    expect(getHolidayName(DateTime(2026, 9, 23), isKorean: true), isNull);
  });

  test('add는 추가·이름 변경, remove는 하드코딩(고정·변동) 목록에서 제외', () {
    HolidayOverrides.current = HolidayOverrides.fromJson({
      'version': 2,
      'add': {'2026-09-23': '임시공휴일', '2030-02-03': '설날', '2026-09-24': '추석 연휴'},
      'remove': ['2026-06-03', '2027-03-01'],
    });
    expect(getHolidayName(DateTime(2026, 9, 23), isKorean: true), '임시공휴일');
    expect(getHolidayName(DateTime(2030, 2, 3), isKorean: true), '설날');
    expect(getHolidayName(DateTime(2026, 9, 24), isKorean: true), '추석 연휴');
    expect(getHolidayName(DateTime(2026, 6, 3), isKorean: true), isNull); // 변동 공휴일 삭제
    expect(getHolidayName(DateTime(2027, 3, 1), isKorean: true), isNull); // 그 해의 고정 공휴일만 삭제
    expect(getHolidayName(DateTime(2028, 3, 1), isKorean: true), '삼일절'); // 다른 해는 그대로
  });

  test('영어 로케일에서는 원격 값이 있어도 표시 안 함(기존 결정 유지)', () {
    HolidayOverrides.current = HolidayOverrides.fromJson({'version': 1, 'add': {'2026-09-23': '임시공휴일'}});
    expect(getHolidayName(DateTime(2026, 9, 23), isKorean: false), isNull);
  });

  test('형식이 틀린 항목은 버리고 나머지만 적용', () {
    final o = HolidayOverrides.fromJson({
      'version': '3',
      'add': {'2026-9-1': 'x', '2026-02-30': '없는날', '2026-10-10': '', '2026-10-11': 12, '2026-10-12': '정상'},
      'remove': ['bad', 2026, '2026-13-01', '2026-10-09'],
    });
    expect(o.version, 0); // 숫자가 아닌 version은 0
    expect(o.add, {'2026-10-12': '정상'});
    expect(o.remove, {'2026-10-09'});
    expect(HolidayOverrides.fromJson(null).add, isEmpty);
  });

  test('캐시 왕복', () {
    final o = HolidayOverrides.fromJson({'version': 5, 'add': {'2027-06-03': '지방선거'}, 'remove': ['2026-06-03']});
    final back = HolidayOverrides.fromJson(o.toJson());
    expect(back.version, 5);
    expect(back.add, o.add);
    expect(back.remove, o.remove);
  });
}
