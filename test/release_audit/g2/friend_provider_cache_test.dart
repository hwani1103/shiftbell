// T13 G2 테스트 - 친구 캐시 확인 상태·refreshAll 호출량 (#21·#30 F)
// 테스트 호스트는 Firebase 미초기화(firebaseReady=false) → 조회 결과가 항상 unavailable(= offline·오류).
// 서버 확인 notFound/revoked 삭제 경로는 Firestore 주입 지점이 없어 여기서 실행하지 못함(NOT_RUN, S9).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/friend_schedule.dart';
import 'package:shiftbell/providers/friend_provider.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:shiftbell/services/firebase_bootstrap.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../g0/g0_support.dart';

class _CountingFriendNotifier extends FriendNotifier {
  int loads = 0;

  @override
  Future<void> load() {
    loads++;
    return super.load();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Database db;

  final cached = FriendScheduleData(
    ownerName: '캐시친구',
    isRegular: false,
    shiftColors: const {'주': 0xff000000},
    assignedDates: const {'2026-09-20': '주'},
    updatedAt: DateTime(2026, 9, 1),
  );

  Future<int> insertFriend(String ownerId, {String? dataJson}) {
    final now = DateTime(2026, 9, 1).toIso8601String();
    return db.insert('friends', {
      'name': 'n_$ownerId',
      'owner_id': ownerId,
      'data_json': dataJson,
      'added_at': now,
      'updated_at': now,
    });
  }

  setUpAll(() async {
    initFfi();
    dir = await Directory.systemTemp.createTemp('g2_friend_provider_');
    await databaseFactory.setDatabasesPath(dir.path);
    db = await DatabaseService.instance.database;
  });

  tearDownAll(() async {
    await db.close();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  setUp(() async {
    firebaseReady = false;
    await db.delete('friends');
  });

  test('F-P01 확인 불가(unavailable) 새로고침은 친구·캐시를 지우지 않고 unconfirmed로 표시 (#21)', () async {
    final id = await insertFriend('ownerA', dataJson: cached.encodeToJsonString());
    final n = _CountingFriendNotifier();
    addTearDown(n.dispose);

    await n.refreshAll(force: true);
    expect(n.state, hasLength(1));
    expect(n.state.single.data?.ownerName, '캐시친구');
    expect(n.state.single.availability, FriendAvailability.unconfirmed);

    expect(await n.refreshFriend(id, 'ownerA'), FriendRefreshResult.unavailable);
    expect(n.state.single.data?.assignedDates, {'2026-09-20': '주'});
    expect(await db.query('friends'), hasLength(1));
  });

  test('F-P02 refreshAll은 친구 수와 무관하게 마지막에 load 1회 (#30)', () async {
    for (final o in ['o1', 'o2', 'o3']) {
      await insertFriend(o, dataJson: cached.encodeToJsonString());
    }
    final n = _CountingFriendNotifier();
    addTearDown(n.dispose);

    await n.refreshAll(force: true);
    // 생성자 초기 load 1 + refreshAll 끝 1
    expect(n.loads, 2);
    expect(n.state, hasLength(3));
    expect(n.state.every((f) => f.availability == FriendAvailability.unconfirmed), isTrue);
  });

  test('F-P03 2분 스로틀: 비강제 재호출은 건너뛰고 force는 다시 실행 (#30)', () async {
    await insertFriend('o1');
    final n = _CountingFriendNotifier();
    addTearDown(n.dispose);

    await n.refreshAll();
    expect(n.loads, 2);
    await insertFriend('o2');
    await n.refreshAll();
    expect(n.loads, 2, reason: '스로틀 안 비강제 호출은 조회·load 없음');
    expect(n.state, hasLength(1));
    await n.refreshAll(force: true);
    expect(n.loads, 3);
    expect(n.state, hasLength(2));
  });

  test('F-P04 생성 직후 자동 새로고침도 초기 SQLite load를 기다린 뒤 전체 친구를 처리', () async {
    await insertFriend('o1');
    await insertFriend('o2');
    final n = FriendNotifier();
    addTearDown(n.dispose);

    await n.refreshAll();
    expect(n.state, hasLength(2));
    expect(n.state.every((f) => f.availability == FriendAvailability.unconfirmed), isTrue);
  });

  test('F-P05 깨졌거나 경계 밖 캐시는 data null로 표시하고 목록은 유지', () async {
    await insertFriend('broken', dataJson: '{not json');
    await insertFriend('badType', dataJson: '{"ownerName":"x","isRegular":"no","updatedAt":"2026-09-01T00:00:00.000"}');
    // 교차 검토 X-11 - 1.0.22에서 만든 80자 초과 이름 캐시는 거부하지 않고 80자로 잘라 표시
    await insertFriend('longName', dataJson: '{"ownerName":"${'a' * 81}","isRegular":false,"updatedAt":"2026-09-01T00:00:00.000"}');
    final n = FriendNotifier();
    addTearDown(n.dispose);

    await n.load();
    expect(n.state, hasLength(3));
    expect(n.state.where((f) => f.data == null), hasLength(2));
    expect(n.state.where((f) => f.data != null).single.data!.ownerName, 'a' * 80);
  });

  test('F-P06 친구 추가: 잘못된 코드·중복 거부, 확인 불가면 등록 후 unconfirmed', () async {
    final n = FriendNotifier();
    addTearDown(n.dispose);
    await n.load();

    expect(await n.addFriend(displayName: '', code: 'SB1:abc'), isFalse);
    expect(await n.addFriend(displayName: '', code: 'SB2:bad/id'), isFalse);
    expect(await n.addFriend(displayName: ' 친구 ', code: 'SB2:ownerNew'), isTrue);
    expect(n.state.single.ownerId, 'ownerNew');
    expect(n.state.single.name, '친구');
    expect(n.state.single.data, isNull);
    expect(n.state.single.availability, FriendAvailability.unconfirmed);
    expect(await n.addFriend(displayName: 'x', code: 'SB2:ownerNew'), isFalse);
    expect(await db.query('friends'), hasLength(1));
  });
}
