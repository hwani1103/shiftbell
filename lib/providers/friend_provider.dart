// providers/friend_provider.dart
//
// ⭐ 친구 목록 상태 관리. 로컬 SQLite(friends 테이블)에 코드를 붙여넣은 스냅샷을
// 저장/조회함 - Firebase 연동 전이라 "실시간"은 아니고, 친구가 코드를 새로
// 보내주면 refreshFriend()로 스냅샷만 교체하는 방식.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/friend_schedule.dart';
import '../services/database_service.dart';
import '../services/friend_share_service.dart';

class FriendEntry {
  final int id;
  final String name;
  final FriendScheduleData data;
  final DateTime addedAt;
  final DateTime updatedAt;

  const FriendEntry({
    required this.id,
    required this.name,
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
      final data = FriendScheduleData.decodeFromJsonString(row['data_json'] as String);
      return FriendEntry(
        id: row['id'] as int,
        name: row['name'] as String,
        data: data,
        addedAt: DateTime.tryParse(row['added_at'] as String) ?? DateTime.now(),
        updatedAt: DateTime.tryParse(row['updated_at'] as String) ?? DateTime.now(),
      );
    }).toList();
  }

  // ⭐ 코드 형식이 잘못됐으면 null 반환 (호출부가 "코드가 올바르지 않습니다" 안내)
  Future<bool> addFriend({required String displayName, required String code}) async {
    final data = FriendShareService.decode(code);
    if (data == null) return false;

    await _db.insertFriend(
      name: displayName.trim().isEmpty ? data.ownerName : displayName.trim(),
      dataJson: data.encodeToJsonString(),
      hasMemos: data.hasMemos,
    );
    await load();
    return true;
  }

  Future<bool> refreshFriend(int id, String newCode) async {
    final data = FriendShareService.decode(newCode);
    if (data == null) return false;
    await _db.updateFriendData(id, dataJson: data.encodeToJsonString(), hasMemos: data.hasMemos);
    await load();
    return true;
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
