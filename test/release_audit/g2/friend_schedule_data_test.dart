// T13 G2 테스트 - FriendScheduleData.tryFromJson 입력 방어 (#30 형식·크기 경계 F)
// Firestore 문서와 로컬 캐시는 외부 입력 - 경계 밖이면 화면 모델로 바꾸지 않고 null.
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/friend_schedule.dart';

const _remove = Object();

Map<String, dynamic> _payload([Map<String, Object?> overrides = const {}]) {
  final map = <String, dynamic>{
    'ownerName': ' 홍길동 ',
    'isRegular': true,
    'pattern': ['주', '야'],
    'todayIndex': 1,
    'startDate': '2026-09-14T00:00:00.000',
    'shiftColors': {'주': 0xff2196f3},
    'assignedDates': {'2026-09-20': '휴'},
    'updatedAt': '2026-09-14T10:00:00.000',
  };
  overrides.forEach((key, value) {
    if (identical(value, _remove)) {
      map.remove(key);
    } else {
      map[key] = value;
    }
  });
  return map;
}

void main() {
  FriendScheduleData? parse([Map<String, Object?> o = const {}]) => FriendScheduleData.tryFromJson(_payload(o));

  test('F-D01 정상 규칙적 payload 파싱, 이름 trim', () {
    final data = parse();
    expect(data, isNotNull);
    expect(data!.ownerName, '홍길동');
    expect(data.pattern, ['주', '야']);
    expect(data.assignedDates, {'2026-09-20': '휴'});
  });

  test('F-D02 불규칙은 pattern/todayIndex/startDate 없어도 허용', () {
    expect(parse({'isRegular': false, 'pattern': null, 'todayIndex': null, 'startDate': null}), isNotNull);
    expect(parse({'isRegular': false, 'pattern': _remove, 'todayIndex': _remove, 'startDate': _remove, 'shiftColors': _remove, 'assignedDates': _remove}), isNotNull);
  });

  test('F-D03 ownerName 자료형·길이(80) 경계', () {
    expect(parse({'ownerName': 'a' * 80}), isNotNull);
    // 교차 검토 X-11 - 1.0.22에서 만든 긴 이름은 거부하지 않고 80자로 잘라 사용
    expect(parse({'ownerName': 'a' * 81})?.ownerName, 'a' * 80);
    expect(parse({'ownerName': 123}), isNull);
    expect(parse({'ownerName': _remove}), isNull);
  });

  test('F-D04 자료형 위반 거부', () {
    expect(parse({'isRegular': 'true'}), isNull);
    expect(parse({'pattern': '주,야'}), isNull);
    expect(parse({'todayIndex': '1'}), isNull);
    expect(parse({'startDate': 20260914}), isNull);
    expect(parse({'shiftColors': ['주']}), isNull);
    expect(parse({'assignedDates': 'x'}), isNull);
    expect(parse({'updatedAt': 1}), isNull);
    expect(parse({'updatedAt': _remove}), isNull);
  });

  test('F-D05 pattern 길이(128)·근무명(1..80) 경계', () {
    expect(parse({'pattern': List.filled(128, '주'), 'todayIndex': 0}), isNotNull);
    expect(parse({'pattern': List.filled(129, '주'), 'todayIndex': 0}), isNull);
    expect(parse({'pattern': ['주', '']}), isNull);
    expect(parse({'pattern': ['주', 'a' * 81]}), isNull);
    expect(parse({'pattern': ['주', 3]}), isNull);
  });

  test('F-D06 규칙적 근무의 todayIndex 범위·startDate 필수', () {
    expect(parse({'todayIndex': -1}), isNull);
    expect(parse({'todayIndex': 2}), isNull);
    expect(parse({'todayIndex': null}), isNull);
    expect(parse({'startDate': null}), isNull);
    expect(parse({'startDate': 'not-a-date'}), isNull);
    expect(parse({'updatedAt': 'not-a-date'}), isNull);
  });

  test('F-D07 shiftColors 개수(5000)·ARGB 범위·키 경계', () {
    Map<String, int> colors(int n) => {for (var i = 0; i < n; i++) 'k$i': 0};
    expect(parse({'shiftColors': colors(5000)}), isNotNull);
    expect(parse({'shiftColors': colors(5001)}), isNull);
    expect(parse({'shiftColors': {'주': -1}}), isNull);
    expect(parse({'shiftColors': {'주': 0x100000000}}), isNull);
    expect(parse({'shiftColors': {'주': 0xffffffff}}), isNotNull);
    expect(parse({'shiftColors': {'주': '0xff'}}), isNull);
    expect(parse({'shiftColors': {'': 1}}), isNull);
  });

  test('F-D08 assignedDates 날짜 키 형식·실재 날짜·개수(5000) 경계', () {
    Map<String, String> dates(int n) => {
          for (var i = 0; i < n; i++)
            DateTime.utc(2000, 1, 1).add(Duration(days: i)).toIso8601String().substring(0, 10): '휴',
        };
    expect(parse({'assignedDates': dates(5000)}), isNotNull);
    expect(parse({'assignedDates': dates(5001)}), isNull);
    expect(parse({'assignedDates': {'2026-02-30': '휴'}}), isNull);
    expect(parse({'assignedDates': {'2026-9-20': '휴'}}), isNull);
    expect(parse({'assignedDates': {'2026-09-20T00:00': '휴'}}), isNull);
    expect(parse({'assignedDates': {'2026-09-20': ''}}), isNull);
    expect(parse({'assignedDates': {'2026-09-20': 1}}), isNull);
  });

  test('F-D09 fromJson은 FormatException, 캐시 문자열 왕복 보존', () {
    expect(() => FriendScheduleData.fromJson(_payload({'ownerName': 1})), throwsFormatException);
    final data = parse()!;
    final back = FriendScheduleData.decodeFromJsonString(data.encodeToJsonString());
    expect(back.toJson(), data.toJson());
  });
}
