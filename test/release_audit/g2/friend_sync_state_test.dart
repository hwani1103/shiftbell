// T13 G2 테스트 - FriendSyncService 로컬 공유 상태 머신 (#21·#24·#30 F)
// 테스트 호스트는 Firebase 미초기화(firebaseReady=false)라 제출 결과가 항상 pending이다.
// 서버 ACK 확인·5초 timeout 후 늦은 ACK·rejected 경로는 Firestore 주입 지점이 없어 여기서 실행하지 못함(NOT_RUN, S9).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/services/firebase_bootstrap.dart';
import 'package:shiftbell/services/friend_sync_service.dart';

const kEnabled = 'friend_share_enabled';
const kName = 'friend_share_my_name';
const kIntent = 'friend_share_intent';
const kDirty = 'friend_share_dirty';
const kGen = 'friend_share_generation';
const kDesired = 'friend_share_desired_fingerprint';
const kConfirmed = 'friend_share_confirmed_fingerprint';

ShiftSchedule _schedule([Map<String, String> assigned = const {'2026-09-20': '휴'}]) => ShiftSchedule(
      isRegular: true,
      pattern: const ['주', '야', '비', '휴'],
      todayIndex: 0,
      shiftTypes: const ['주', '야', '비', '휴'],
      startDate: DateTime(2026, 9, 14),
      shiftColors: const {'주': 0xff2196f3},
      assignedDates: assigned,
    );

const _active = <String, Object>{kIntent: 'active', kEnabled: true, kGen: 1, kDirty: false, kName: '홍'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = FriendSyncService.instance;

  setUp(() {
    firebaseReady = false;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => firebaseReady = false);

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  test('F-S01 새 설치: off·회차 0·dirty 없음, intent off 영속', () async {
    final s = await svc.getShareState();
    expect(s.intent, FriendShareIntent.off);
    expect(s.generation, 0);
    expect(s.dirty, isFalse);
    expect((await prefs()).getString(kIntent), 'off');
  });

  test('F-S02 legacy(enabled만 있음) 설치는 active 회차 1·dirty로 올리고 재조회해도 유지', () async {
    SharedPreferences.setMockInitialValues({kEnabled: true, kName: '홍'});
    final s = await svc.getShareState();
    expect((s.intent, s.generation, s.dirty), (FriendShareIntent.active, 1, true));
    final p = await prefs();
    expect((p.getString(kIntent), p.getInt(kGen), p.getBool(kDirty)), ('active', 1, true));
    final again = await svc.getShareState();
    expect((again.intent, again.generation, again.dirty), (FriendShareIntent.active, 1, true));
  });

  test('F-S03 중지: 로컬 즉시 off(enabled false), 서버 확인 전 stop_pending·dirty, 회차 보존 (#24)', () async {
    SharedPreferences.setMockInitialValues({..._active, kGen: 2});
    await svc.stopSharing();
    final s = await svc.getShareState();
    expect((s.intent, s.generation, s.dirty), (FriendShareIntent.stopPending, 2, true));
    expect(await svc.isSharingEnabled(), isFalse);
    final p = await prefs();
    expect((p.getBool(kEnabled), p.getString(kIntent)), (false, 'stop_pending'));
  });

  test('F-S04 stop_pending은 시작·재개·재연결·복원·재시도 어느 진입점에서도 active로 돌아가지 않음 (#24)', () async {
    SharedPreferences.setMockInitialValues({kIntent: 'stop_pending', kEnabled: false, kGen: 2, kDirty: true, kName: '홍'});
    await svc.onAppStarted(_schedule());
    await svc.onAppResumed(_schedule());
    await svc.onNetworkReconnected(_schedule());
    await svc.onRestoreCompleted(_schedule());
    await svc.retryPending(_schedule());
    await svc.syncIfEnabled(_schedule());
    final s = await svc.getShareState();
    expect((s.intent, s.generation, s.dirty), (FriendShareIntent.stopPending, 2, true));
    final p = await prefs();
    expect(p.getBool(kEnabled), isFalse);
    expect(p.getString(kDesired), isNull, reason: '중지 대기 중 근무표 변경이 새 업로드 목표를 만들면 안 됨');
  });

  test('F-S05 중지와 동기화가 겹쳐도 최종 로컬 의도는 stop_pending (부활 없음)', () async {
    SharedPreferences.setMockInitialValues({..._active});
    await Future.wait([svc.stopSharing(), svc.syncIfEnabled(_schedule({'2026-09-21': '주'}))]);
    final s = await svc.getShareState();
    expect(s.intent, FriendShareIntent.stopPending);
    expect((await prefs()).getBool(kEnabled), isFalse);
  });

  test('F-S06 Firebase 준비 전 공유 시작은 null이고 상태를 바꾸지 않음, 빈 이름도 null', () async {
    expect(await svc.startSharing(schedule: _schedule(), ownerName: '홍'), isNull);
    final s = await svc.getShareState();
    expect((s.intent, s.generation), (FriendShareIntent.off, 0));
    final p = await prefs();
    expect((p.getString(kName), p.getBool(kEnabled)), (null, null));

    // 빈 이름 검사는 Firebase 접근보다 먼저 - 준비된 상태여도 네트워크/인증을 건드리지 않고 null
    firebaseReady = true;
    expect(await svc.startSharing(schedule: _schedule(), ownerName: '   '), isNull);
    expect((await svc.getShareState()).intent, FriendShareIntent.off);
  });

  test('F-S07 active 근무표 동기화: 확인 불가면 desired 기록·dirty 유지·confirmed 없음·회차 그대로 (#24)', () async {
    SharedPreferences.setMockInitialValues({..._active});
    await svc.syncIfEnabled(_schedule());
    final p = await prefs();
    expect(p.getString(kDesired), isNotNull);
    expect(p.getBool(kDirty), isTrue);
    expect(p.getString(kConfirmed), isNull);
    final s = await svc.getShareState();
    expect((s.intent, s.generation), (FriendShareIntent.active, 1));
  });

  test('F-S08 off에서는 동기화·재시도가 dirty·desired를 만들지 않음', () async {
    await svc.syncIfEnabled(_schedule());
    await svc.retryPending(_schedule());
    final p = await prefs();
    expect(p.getString(kDesired), isNull);
    expect(p.getBool(kDirty), anyOf(isNull, isFalse));
    expect((await svc.getShareState()).intent, FriendShareIntent.off);
  });

  test('F-S09 변경 기반 업로드(#30): 서버 확인된 동일 payload는 재제출 표시 안 함, map 순서만 다르면 동일, 실제 변경만 dirty', () async {
    SharedPreferences.setMockInitialValues({..._active});
    await svc.syncIfEnabled(_schedule({'2026-09-20': '휴', '2026-09-21': '주'}));
    final p = await prefs();
    final d1 = p.getString(kDesired)!;
    // 서버 확인(_confirmActive)과 같은 결과를 직접 기록 - 확인 경로 자체는 주입 지점이 없어 NOT_RUN
    await p.setString(kConfirmed, d1);
    await p.setBool(kDirty, false);

    await svc.syncIfEnabled(_schedule({'2026-09-21': '주', '2026-09-20': '휴'}));
    expect(p.getBool(kDirty), isFalse, reason: '키 순서만 다른 동일 내용');
    expect(p.getString(kDesired), d1);

    await svc.syncIfEnabled(_schedule({'2026-09-20': '주'}));
    expect(p.getBool(kDirty), isTrue);
    expect(p.getString(kDesired), isNot(d1));
    expect((await svc.getShareState()).generation, 1, reason: '정상 수정은 회차를 올리지 않음');
  });

  test('F-S10 dirty가 남아 있으면 같은 payload라도 재시도 대상 유지', () async {
    SharedPreferences.setMockInitialValues({..._active});
    await svc.syncIfEnabled(_schedule());
    final p = await prefs();
    await p.setString(kConfirmed, p.getString(kDesired)!);
    // dirty=true 그대로 → 재개 시 다시 제출 시도(준비 전이라 pending) 후에도 dirty 유지
    await svc.onAppResumed(_schedule());
    expect(p.getBool(kDirty), isTrue);
  });

  test('F-S11 경계 밖 스케줄은 업로드 목표를 바꾸지 않고 dirty만 남김', () async {
    SharedPreferences.setMockInitialValues({..._active});
    await svc.syncIfEnabled(_schedule());
    final p = await prefs();
    final d1 = p.getString(kDesired)!;
    await p.setString(kConfirmed, d1);
    await p.setBool(kDirty, false);

    await svc.syncIfEnabled(_schedule({'2026-02-30': '휴'}));
    expect(p.getBool(kDirty), isTrue);
    expect(p.getString(kDesired), d1);
  });

  test('F-S12 이름 변경: 공유 중 아니면 false·미저장, 공유 중 확인 불가면 false지만 이름 저장·dirty (화면은 대기 안내)', () async {
    expect(await svc.updateMyName(newName: '새이름', schedule: _schedule()), isFalse);
    expect((await prefs()).getString(kName), isNull);

    SharedPreferences.setMockInitialValues({..._active});
    expect(await svc.updateMyName(newName: '  ', schedule: _schedule()), isFalse);
    expect(await svc.updateMyName(newName: ' 새이름 ', schedule: _schedule()), isFalse);
    final p = await prefs();
    expect(p.getString(kName), '새이름');
    expect(p.getBool(kDirty), isTrue);
    expect(p.getString(kDesired), isNotNull);
    final s = await svc.getShareState();
    expect((s.intent, s.generation, s.dirty), (FriendShareIntent.active, 1, true));
  });

  test('F-S13 복원 완료 진입점: active면 dirty로 재업로드 대기, off면 변화 없음', () async {
    await svc.onRestoreCompleted(_schedule());
    expect((await prefs()).getBool(kDirty), anyOf(isNull, isFalse));

    SharedPreferences.setMockInitialValues({..._active});
    await svc.onRestoreCompleted(_schedule());
    expect((await prefs()).getBool(kDirty), isTrue);
  });

  test('F-S14 준비 전·잘못된 ownerId 조회는 unavailable - 서버 확인 삭제로 오인하지 않음 (#21)', () async {
    for (final id in ['abc', 'a/b', '']) {
      final r = await svc.fetchByOwnerIdDetailed(id);
      expect(r.status, FriendFetchStatus.unavailable, reason: id);
      expect(r.serverConfirmedUnavailable, isFalse);
      expect(r.data, isNull);
    }
    expect(await svc.fetchByOwnerId('abc'), isNull);
  });

  test('F-S15 공유 상태 키 7개는 전부 백업 제외 목록에 있음 (G4 인계)', () {
    expect(FriendSyncService.backupExcludedPreferenceKeys, {kEnabled, kName, kIntent, kDirty, kGen, kDesired, kConfirmed});
  });
}
