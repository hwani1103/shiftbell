// services/friend_share_service.dart
//
// ⭐ 친구 공유 코드 인코딩/디코딩 - v1(Firestore) 전환 이후, 코드/링크에는 전체 데이터가
// 아니라 Firestore 문서 ID(ownerId) "하나만" 담김. 그래서 코드가 영구적으로 유효하고,
// 친구가 몇 번을 다시 열어도 그 순간 Firestore의 최신 스케줄을 새로 fetch해서 보여줄 수
// 있음 (예전 SB1: 포맷은 스케줄 전체를 그 자리에서 base64로 박제하는 "스냅샷"이라 링크를
// 다시 열어도 절대 갱신이 안 됐음 - 친구공유_v1_스펙.md 참고).
class FriendShareService {
  // ⭐ 버전 프리픽스 - SB1:은 예전 "전체 스냅샷" 포맷이라 더 이상 디코딩하지 않음
  // (그 코드를 아직 들고 있는 사용자는 새로 코드를 받아야 함 - 베타 단계라 감수).
  static const _prefix = 'SB2:';

  static String encodeOwnerId(String ownerId) => '$_prefix$ownerId';

  /// 코드/링크 문자열에서 ownerId만 뽑아냄. 형식이 아니거나 비어있으면 null.
  static String? decodeOwnerId(String code) {
    final trimmed = code.trim();
    if (!trimmed.startsWith(_prefix)) return null;
    final ownerId = trimmed.substring(_prefix.length).trim();
    if (ownerId.isEmpty) return null;
    return ownerId;
  }
}
