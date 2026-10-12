// lib/services/diag_log.dart
//
// 진단 기록의 Dart 진입점. 네이티브 DiagLog.kt가 기기 내부에 먼저 쓰고,
// Download/ShiftBell/log의 최신 진단 파일을 자동 갱신한다. 해석은 docs/진단로그_해석_매뉴얼.md.
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
}
