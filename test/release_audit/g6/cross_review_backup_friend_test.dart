// 출시전 교차 검토(docs/release_audit/g6/codex_prerelease_diff_review.md) 반영분 - Dart 순수 로직 회귀 테스트
//  - X-09 복원 검증이 설정 키별 자료형과 DB 날짜 저장 형식을 확인
//  - X-11 1.0.22에서 만든 80자 초과 공유 이름을 거부하지 않고 잘라서 사용
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/backup_payload.dart';
import 'package:shiftbell/models/friend_schedule.dart';
import 'package:shiftbell/services/backup_policy.dart';
import 'package:shiftbell/services/backup_validator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

BackupPayload _payload({
  Map<String, dynamic> preferences = const {},
  List<Map<String, dynamic>> alarms = const [],
}) =>
    BackupPayload(
      schemaVersion: kBackupSchemaVersion,
      exportedAt: DateTime(2026, 9, 14),
      appVersionName: '1.0.23',
      appVersionCode: 25,
      tables: {
        'alarm_types': [
          {'id': 1, 'name': 'Sound'},
        ],
        if (alarms.isNotEmpty) 'alarms': alarms,
      },
      preferences: preferences,
    );

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE alarm_types(id INTEGER PRIMARY KEY, name TEXT)');
    await db.execute(
      'CREATE TABLE alarms(id INTEGER PRIMARY KEY, time TEXT, date TEXT, type TEXT, alarm_type_id INTEGER, shift_type TEXT)',
    );
  });

  tearDown(() async => db.close());

  group('X-09 복원 검증 - 설정 자료형', () {
    test('등록된 bool 키에 문자열이면 거부', () async {
      final issues = await BackupValidator.validate(_payload(preferences: {'schedule_tab_enabled': 'false'}), db);
      expect(issues, contains('preference schedule_tab_enabled type mismatch'));
    });

    test('등록된 키의 올바른 자료형·등록 안 된 기본 자료형은 통과', () async {
      final issues = await BackupValidator.validate(
        _payload(preferences: {
          'schedule_tab_enabled': false,
          'all_teams_names': ['1조', '2조'],
          'some_future_setting': 3,
        }),
        db,
      );
      expect(issues, isEmpty);
    });

    test('자료형 등록표와 판정 함수가 일치', () {
      expect(backupPrefValueMatches(BackupPrefType.boolean, true), isTrue);
      expect(backupPrefValueMatches(BackupPrefType.integer, 1.5), isFalse);
      expect(backupPrefValueMatches(BackupPrefType.stringList, ['a', 1]), isFalse);
    });
  });

  group('X-09 복원 검증 - 알람 날짜 저장 형식', () {
    Map<String, dynamic> alarm(String date) =>
        {'id': 1, 'time': '07:00', 'date': date, 'type': 'custom', 'alarm_type_id': 1, 'shift_type': '주'};

    test('초 단위·밀리초 형식은 통과', () async {
      expect(await BackupValidator.validate(_payload(alarms: [alarm('2030-01-01T07:00:00')]), db), isEmpty);
      expect(await BackupValidator.validate(_payload(alarms: [alarm('2030-01-01T07:00:00.000')]), db), isEmpty);
    });

    test('파싱은 되지만 저장 형식이 아니면 거부', () async {
      final issues = await BackupValidator.validate(_payload(alarms: [alarm('2030-01-01 07:00')]), db);
      expect(issues, contains('alarms date invalid'));
    });
  });

  group('X-11 긴 공유 이름', () {
    Map<String, dynamic> friend(String name) => {
          'ownerName': name,
          'isRegular': false,
          'updatedAt': '2026-09-14T10:00:00.000',
        };

    test('80자 초과 이름은 거부하지 않고 80자로 자름', () {
      final data = FriendScheduleData.tryFromJson(friend('가' * 120));
      expect(data, isNotNull);
      expect(data!.ownerName, '가' * 80);
    });

    test('clampOwnerName은 80자 이하를 그대로 둠', () {
      expect(FriendScheduleData.clampOwnerName('홍길동'), '홍길동');
      expect(FriendScheduleData.clampOwnerName('a' * 81).length, 80);
    });
  });
}
