// services/friend_share_service.dart
//
// ⭐ 친구 공유 코드 인코딩/디코딩. Firebase 없이도 당장 동작하게 만든 "1회성
// 내보내기/가져오기" 방식 - 친구가 내 코드를 카카오톡 등으로 받아서 앱에
// 붙여넣으면 그 시점 스냅샷이 저장됨(실시간 동기화 아님). 나중에 Firebase를
// 붙이면 이 서비스의 encode()/decode() 포맷은 그대로 두고, FriendProvider가
// "코드 붙여넣기" 대신 "Firestore 문서 구독"으로 데이터를 얻어오도록만 바꾸면
// 되게 설계해둠 (아래 FriendScheduleData 자체가 이미 Firestore에 그대로 넣을
// 수 있는 JSON 모양이라 마이그레이션이 가벼움).
import 'dart:convert';
import '../models/friend_schedule.dart';

class FriendShareService {
  // ⭐ 버전 프리픽스 - 나중에 포맷이 바뀌어도 예전 코드/새 코드를 구분할 수 있게.
  static const _prefix = 'SB1:';

  static String encode(FriendScheduleData data) {
    final jsonStr = data.encodeToJsonString();
    final b64 = base64Url.encode(utf8.encode(jsonStr));
    return '$_prefix$b64';
  }

  /// 실패하면 null 반환 (형식 오류/손상된 코드 등 - 호출부가 사용자에게 안내함).
  static FriendScheduleData? decode(String code) {
    try {
      final trimmed = code.trim();
      if (!trimmed.startsWith(_prefix)) return null;
      final b64 = trimmed.substring(_prefix.length);
      final jsonStr = utf8.decode(base64Url.decode(b64));
      return FriendScheduleData.decodeFromJsonString(jsonStr);
    } catch (e) {
      return null;
    }
  }
}
