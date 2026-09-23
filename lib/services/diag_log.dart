// lib/services/diag_log.dart
//
// ⭐ 2026-09-23 (1.0.24 C) - 문제 진단 기록의 Dart 진입점. 실제 파일은 네이티브 DiagLog.kt가 기기 안(Device Protected 저장소)에만
// 쓰고, 사용자가 설정에서 "문제 신고용 진단 파일"을 만들 때만 밖으로 나간다. 해석은 docs/진단로그_해석_매뉴얼.md.
//
// ⚠️ fields에 메모·일정 내용, 근무명, 친구 이름, 공유 코드를 넣지 말 것(개인정보처리방침과 일치해야 함). 종류·개수·결과 코드만.

import 'package:flutter/foundation.dart';

import '../constants/platform_channel.dart';

class DiagLog {
  DiagLog._();

  /// 기록하고 잊는다. 웹·테스트 등 채널이 없으면 조용히 무시.
  static void log(String event, [Map<String, Object?> fields = const {}]) {
    if (kIsWeb) return;
    kAlarmChannel.invokeMethod('diagLog', {'event': event, 'fields': fields}).catchError((_) => null);
  }

  /// 진단 파일을 Download/ShiftBell에 저장하고 공유 시트를 연다. 저장에 성공하면 true(공유를 취소해도 파일은 남음).
  static Future<bool> exportAndShare({required String chooserTitle}) async {
    if (kIsWeb) return false;
    try {
      final uri = await kAlarmChannel.invokeMethod<String>('exportDiagnostics', {'chooserTitle': chooserTitle});
      return uri != null;
    } catch (_) {
      return false;
    }
  }
}
