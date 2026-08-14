// services/friend_sync_service.dart
//
// ⭐ 친구공유 v1 - Firestore 연동. friend_schedules/{ownerId} 문서에 내 스케줄을
// upsert하고, 친구의 ownerId로 최신 스케줄을 1회 fetch함 (실시간 스트리밍 아님 - "열 때/
// 새로고침할 때"만 조회, 친구공유_v1_스펙.md 참고). Firebase가 아직 설정 안 됐으면
// (firebaseReady == false) 모든 메서드가 조용히 no-op/null을 반환해서 앱의 나머지 기능에는
// 영향이 없음.
//
// ⭐ ownerId = Firebase 익명 인증(Anonymous Auth) uid. 로그인 화면 없이도 기기마다
// 안정적인 uid를 받을 수 있고(로그아웃하지 않는 한 재설치 전까지 유지), 무엇보다
// firestore.rules가 "본인 문서만 write 가능"을 실제로 강제하려면 이게 필요함 - 그냥
// 로컬에서 생성한 UUID는 "문서 ID를 아는 사람이면 누구나(=친구도!) write 가능"해지는
// 구멍이 있어서(코드를 공유하는 순간 read용 ID와 write용 ID가 같은 값이 되어버림),
// uid 기반 write 검증 없이는 친구가 실수로/악의적으로 내 스케줄을 덮어쓰는 것도 막을
// 방법이 없음. 사용자가 Firebase 콘솔에서 "Anonymous" 로그인 방법만 켜주면 됨(무료).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/friend_schedule.dart';
import '../models/shift_schedule.dart';
import 'firebase_bootstrap.dart';

class FriendSyncService {
  FriendSyncService._();
  static final instance = FriendSyncService._();

  static const _kEnabledKey = 'friend_share_enabled';
  static const _kMyNameKey = 'friend_share_my_name';

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('friend_schedules');

  // ⭐ 이 기기의 공유 문서 ID(=익명 인증 uid). 이미 로그인돼 있으면 그대로, 아니면
  // 새로 익명 로그인함. Firebase 미설정/오프라인이면 null.
  Future<String?> getOrCreateOwnerId() async {
    if (!firebaseReady) return null;
    try {
      final auth = FirebaseAuth.instance;
      final current = auth.currentUser;
      if (current != null) return current.uid;
      final cred = await auth.signInAnonymously();
      return cred.user?.uid;
    } catch (e) {
      print('⚠️ 친구공유 익명 로그인 실패: $e');
      return null;
    }
  }

  Future<bool> isSharingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabledKey) ?? false;
  }

  Future<String?> savedMyName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kMyNameKey);
  }

  /// "공유 시작하기" 최초 실행 시 호출 - 공유를 켜고 최초 upsert. 실패하면(로그인 실패
  /// 등) null - 호출부가 사용자에게 실패를 안내함.
  Future<String?> startSharing({required ShiftSchedule schedule, required String ownerName}) async {
    final ownerId = await getOrCreateOwnerId();
    if (ownerId == null) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, true);
    await prefs.setString(_kMyNameKey, ownerName);
    await _upsert(ownerId, schedule, ownerName);
    return ownerId;
  }

  /// 스케줄이 바뀔 때마다(근무변경/패턴수정 등) 호출 - 공유를 한 번도 시작 안 했으면
  /// 아무 일도 안 함(불필요한 Firestore 쓰기 방지). schedule_provider.dart가 스케줄을
  /// 저장하는 모든 지점에서 호출함.
  Future<void> syncIfEnabled(ShiftSchedule? schedule) async {
    if (schedule == null || !firebaseReady) return;
    try {
      if (!await isSharingEnabled()) return;
      final ownerId = await getOrCreateOwnerId();
      if (ownerId == null) return;
      final name = await savedMyName() ?? '친구';
      await _upsert(ownerId, schedule, name);
    } catch (e) {
      // ⭐ 오프라인/미설정 등으로 실패해도 스케줄 자체 저장(로컬 DB)은 이미 끝난 뒤라
      // 조용히 무시 - 다음 변경 때, 또는 친구가 새로고침할 때 다시 반영 시도됨.
      print('⚠️ 친구공유 동기화 실패(무시): $e');
    }
  }

  /// 이미 공유 중일 때 "친구에게 보일 이름"만 바꿈 - ownerId/코드/링크는 그대로 유지되고
  /// Firestore 문서의 ownerName 필드만 갱신됨. 실패하면(오프라인 등) false - 호출부가
  /// 로컬 표시는 유지한 채 안내만 함.
  Future<bool> updateMyName({required String newName, required ShiftSchedule schedule}) async {
    if (!firebaseReady) return false;
    final ownerId = await getOrCreateOwnerId();
    if (ownerId == null) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kMyNameKey, newName);
      await _upsert(ownerId, schedule, newName);
      return true;
    } catch (e) {
      print('⚠️ 공유 이름 변경 실패: $e');
      return false;
    }
  }

  /// 공유 중지 - 이후 syncIfEnabled가 조용히 no-op되도록 로컬 플래그를 끄고, Firestore
  /// 문서도 지워서 이미 코드/링크를 받은 친구도 더 이상 내 스케줄을 못 보게 함.
  Future<void> stopSharing() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, false);
    if (!firebaseReady) return;
    try {
      final ownerId = await getOrCreateOwnerId();
      if (ownerId == null) return;
      await _col.doc(ownerId).delete();
    } catch (e) {
      print('⚠️ 공유 중지 시 Firestore 문서 삭제 실패(무시): $e');
    }
  }

  Future<void> _upsert(String ownerId, ShiftSchedule schedule, String ownerName) async {
    await _col.doc(ownerId).set({
      'ownerName': ownerName,
      'isRegular': schedule.isRegular,
      'pattern': schedule.pattern,
      'todayIndex': schedule.todayIndex,
      'startDate': schedule.startDate?.toIso8601String(),
      'shiftColors': schedule.shiftColors ?? {},
      'assignedDates': schedule.assignedDates ?? {},
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 친구의 ownerId로 최신 스케줄을 1회 조회. 문서가 없거나(친구가 공유를 중단/삭제)
  /// Firebase 미설정/오프라인이면 null - 호출부가 "동기화 실패"를 안내함. 읽기는 로그인
  /// 없이도 되지만(firestore.rules 참고), 웹뷰어에서도 규칙이 요구하면 통하도록 여기서도
  /// 먼저 익명 로그인을 시도해둠 - 이미 로그인돼 있으면 비용 없음.
  Future<FriendScheduleData?> fetchByOwnerId(String ownerId) async {
    if (!firebaseReady) return null;
    try {
      await getOrCreateOwnerId();
      final snap = await _col.doc(ownerId).get();
      final raw = snap.data();
      if (!snap.exists || raw == null) return null;

      final updatedAtRaw = raw['updatedAt'];
      final updatedAtIso = updatedAtRaw is Timestamp ? updatedAtRaw.toDate().toIso8601String() : null;

      return FriendScheduleData.fromJson({
        'ownerName': raw['ownerName'],
        'isRegular': raw['isRegular'],
        'pattern': raw['pattern'],
        'todayIndex': raw['todayIndex'],
        'startDate': raw['startDate'],
        'shiftColors': raw['shiftColors'],
        'assignedDates': raw['assignedDates'],
        'updatedAt': updatedAtIso,
      });
    } catch (e) {
      print('⚠️ 친구 스케줄 조회 실패: $e');
      return null;
    }
  }
}
