// providers/friend_provider.dart
//
// ⭐ 친구 목록 상태 관리 - 친구공유 v1(Firestore). 로컬 SQLite(friends 테이블)엔 "누구를
// 추가했는지"(ownerId)와 마지막으로 성공한 조회 결과 캐시만 있고, 실제 최신 데이터는
// FriendSyncService를 통해 Firestore에서 매번 새로 받아옴 - 그래서 addFriend/refreshFriend
// 둘 다 네트워크에 의존하고, 실패해도(오프라인 등) 친구 자체는 등록/유지되고 캐시된
// 마지막 데이터를 보여줌.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/friend_schedule.dart';
import '../services/database_service.dart';
import '../services/friend_share_service.dart';
import '../services/friend_sync_service.dart';

enum FriendAvailability { unknown, available, unconfirmed, invalid }

enum FriendRefreshResult { refreshed, serverRemoved, unavailable, invalid }

class FriendEntry {
  final int id;
  final String name;
  final String ownerId;
  final FriendScheduleData? data; // ⭐ null이면 아직 한 번도 조회 성공 못 한 상태
  final DateTime addedAt;
  final DateTime updatedAt;
  final FriendAvailability availability;

  const FriendEntry({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.data,
    required this.addedAt,
    required this.updatedAt,
    this.availability = FriendAvailability.unknown,
  });
}

class FriendNotifier extends StateNotifier<List<FriendEntry>> {
  FriendNotifier() : super([]) {
    load();
  }

  final _db = DatabaseService.instance;
  final Map<String, FriendAvailability> _availabilityByOwnerId = {};

  FriendScheduleData? _decodeCachedSchedule(String? rawJson) {
    if (rawJson == null) return null;
    try {
      return FriendScheduleData.decodeFromJsonString(rawJson);
    } catch (error) {
      print('⚠️ 친구 스케줄 캐시 형식 오류: $error');
      return null;
    }
  }

  Future<void> load() async {
    final rows = await _db.getAllFriends();
    state = rows.map((row) {
      final rawJson = row['data_json'] as String?;
      return FriendEntry(
        id: row['id'] as int,
        name: row['name'] as String,
        ownerId: row['owner_id'] as String,
        data: _decodeCachedSchedule(rawJson),
        addedAt: DateTime.tryParse(row['added_at'] as String) ?? DateTime.now(),
        updatedAt: DateTime.tryParse(row['updated_at'] as String) ?? DateTime.now(),
        availability:
            _availabilityByOwnerId[row['owner_id'] as String] ??
                FriendAvailability.unknown,
      );
    }).toList();
  }

  // ⭐ 코드 형식이 잘못됐거나 이미 추가된 친구면 false (호출부가 "코드가 올바르지
  // 않아요/이미 추가된 친구예요" 안내). Firestore 조회 자체가 실패해도(오프라인 등)
  // 친구는 일단 등록됨 - 데이터는 나중에 "새로고침"으로 다시 받을 수 있음.
  Future<bool> addFriend({required String displayName, required String code}) async {
    final ownerId = FriendShareService.decodeOwnerId(code);
    if (ownerId == null) return false;

    final existing = await _db.getAllFriends();
    if (existing.any((row) => row['owner_id'] == ownerId)) return false;

    final fetch =
        await FriendSyncService.instance.fetchByOwnerIdDetailed(ownerId);
    if (fetch.serverConfirmedUnavailable ||
        fetch.status == FriendFetchStatus.invalid) {
      return false;
    }
    final data = fetch.data;
    // ⭐ 영어 현지화: 여기(Riverpod Notifier)는 BuildContext가 없어서 언어별 기본
    // 문구를 고를 수 없음 - 빈 문자열로 저장해두고, 실제 화면에 표시할 때(예:
    // friend_list_screen.dart)가 비어있으면 context.l10n.friendDefaultDisplayName로
    // 대체함(friend_schedule.dart의 ownerName 처리와 동일한 패턴).
    final name = displayName.trim().isNotEmpty ? displayName.trim() : (data?.ownerName ?? '');

    try {
      await _db.insertFriend(name: name, ownerId: ownerId, dataJson: data?.encodeToJsonString());
    } catch (e) {
      // ⭐ owner_id UNIQUE 제약 등 - 위에서 이미 걸러지지만 동시 추가 등 드문 경합 대비.
      print('⚠️ 친구 추가 실패: $e');
      return false;
    }
    _availabilityByOwnerId[ownerId] = data == null
        ? FriendAvailability.unconfirmed
        : FriendAvailability.available;
    await load();
    return true;
  }

  Future<FriendRefreshResult> _refreshWithoutLoad(
      int id, String ownerId) async {
    final fetch =
        await FriendSyncService.instance.fetchByOwnerIdDetailed(ownerId);
    switch (fetch.status) {
      case FriendFetchStatus.found:
        await _db.updateFriendData(
            id, dataJson: fetch.data!.encodeToJsonString());
        _availabilityByOwnerId[ownerId] = FriendAvailability.available;
        return FriendRefreshResult.refreshed;
      case FriendFetchStatus.notFound:
      case FriendFetchStatus.revoked:
        // Source.server가 확인한 삭제/중지만 로컬 캐시와 등록 항목을 제거한다.
        await _db.deleteFriend(id);
        _availabilityByOwnerId.remove(ownerId);
        return FriendRefreshResult.serverRemoved;
      case FriendFetchStatus.unavailable:
        _availabilityByOwnerId[ownerId] = FriendAvailability.unconfirmed;
        return FriendRefreshResult.unavailable;
      case FriendFetchStatus.invalid:
        _availabilityByOwnerId[ownerId] = FriendAvailability.invalid;
        return FriendRefreshResult.invalid;
    }
  }

  /// 서버 확인 삭제/중지는 제거하고, offline·오류는 캐시를 유지한 채 확인 불가로 둔다.
  Future<FriendRefreshResult> refreshFriend(int id, String ownerId) async {
    final result = await _refreshWithoutLoad(id, ownerId);
    await load();
    return result;
  }

  // ⭐ "새로고침" 버튼을 없애고 화면 진입마다 조용히 자동 새로고침하는 방식으로
  // 바꾸면서 추가한 스로틀 - 예전 방식(수동 버튼/pull-to-refresh만)은 사용자가
  // 안 누르면 안 갱신됐는데, 자동으로 바꾸면 반대로 "일정공유 탭을 자주 왔다갔다"
  // 하는 사용자가 매번 전체 친구 수만큼 Firestore 읽기를 반복하게 됨 - 마지막
  // 전체 새로고침이 이 시간 이내면 건너뜀.
  static const _refreshAllThrottle = Duration(minutes: 2);
  DateTime? _lastRefreshAllAt;

  /// 친구 목록 전체 새로고침.
  /// - [force]=false(기본, 화면 진입 시 자동 호출용): 마지막 전체 새로고침이
  ///   [_refreshAllThrottle] 이내면 조용히 건너뜀(불필요한 반복 Firestore 읽기 방지).
  /// - [force]=true(pull-to-refresh 등 사용자가 명시적으로 당겼을 때): 스로틀
  ///   무시하고 무조건 새로 받아옴.
  Future<void> refreshAll({bool force = false}) async {
    if (!force && _lastRefreshAllAt != null &&
        DateTime.now().difference(_lastRefreshAllAt!) < _refreshAllThrottle) {
      return;
    }
    _lastRefreshAllAt = DateTime.now();
    final snapshot = List<FriendEntry>.from(state);
    for (final friend in snapshot) {
      await _refreshWithoutLoad(friend.id, friend.ownerId);
    }
    // 친구마다 전체 SQLite 목록을 다시 읽지 않고 모든 fetch/update 뒤 한 번만 읽는다.
    await load();
  }

  Future<void> removeFriend(int id) async {
    final ownerIds = state.where((friend) => friend.id == id).map((e) => e.ownerId);
    for (final ownerId in ownerIds) {
      _availabilityByOwnerId.remove(ownerId);
    }
    await _db.deleteFriend(id);
    await load();
  }

  Future<void> renameFriend(int id, String name) async {
    if (name.trim().isEmpty) return;
    await _db.renameFriend(id, name.trim());
    await load();
  }
}

final friendProvider = StateNotifierProvider<FriendNotifier, List<FriendEntry>>(
  (ref) => FriendNotifier(),
);
