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

class FriendEntry {
  final int id;
  final String name;
  final String ownerId;
  final FriendScheduleData? data; // ⭐ null이면 아직 한 번도 조회 성공 못 한 상태
  final DateTime addedAt;
  final DateTime updatedAt;

  const FriendEntry({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.data,
    required this.addedAt,
    required this.updatedAt,
  });
}

class FriendNotifier extends StateNotifier<List<FriendEntry>> {
  FriendNotifier() : super([]) {
    load();
  }

  final _db = DatabaseService.instance;

  Future<void> load() async {
    final rows = await _db.getAllFriends();
    state = rows.map((row) {
      final rawJson = row['data_json'] as String?;
      return FriendEntry(
        id: row['id'] as int,
        name: row['name'] as String,
        ownerId: row['owner_id'] as String,
        data: rawJson != null ? FriendScheduleData.decodeFromJsonString(rawJson) : null,
        addedAt: DateTime.tryParse(row['added_at'] as String) ?? DateTime.now(),
        updatedAt: DateTime.tryParse(row['updated_at'] as String) ?? DateTime.now(),
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

    final data = await FriendSyncService.instance.fetchByOwnerId(ownerId);
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
    await load();
    return true;
  }

  /// 친구 한 명의 최신 스케줄을 Firestore에서 다시 받아옴. 실패하면(오프라인/문서 삭제됨)
  /// 캐시를 건드리지 않고 false만 반환.
  Future<bool> refreshFriend(int id, String ownerId) async {
    final data = await FriendSyncService.instance.fetchByOwnerId(ownerId);
    if (data == null) return false;
    await _db.updateFriendData(id, dataJson: data.encodeToJsonString());
    await load();
    return true;
  }

  /// 친구 목록 전체 새로고침 - 목록 화면 진입 시/당겨서 새로고침 시 호출.
  Future<void> refreshAll() async {
    for (final friend in state) {
      await refreshFriend(friend.id, friend.ownerId);
    }
  }

  Future<void> removeFriend(int id) async {
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
