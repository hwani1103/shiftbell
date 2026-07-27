// lib/services/alarm_refresh_service.dart

import 'package:flutter/services.dart';

/// ⭐ 알람 자동 갱신 트리거 (실제 갱신 로직은 Native AlarmRefreshEngine이 유일하게 수행함)
///
/// 예전엔 이 클래스가 Dart(sqflite)에서 "전체 삭제 → 10일치 재생성"을 직접 수행했는데,
/// Native(Kotlin)에도 똑같은 일을 하는 별도 구현이 있었고, "오늘 이미 갱신했는지" 판단도
/// 서로 다른 저장소에 따로 했었음. 그래서 날짜가 바뀐 직후 앱을 열면 Dart/Native가 각자
/// "갱신 필요"라고 동시에 판단해서 거의 동시에 두 번 실행됐고, 게다가 Dart 쪽 삭제는
/// type 필터가 없어서 스누즈 중인 알람까지 통째로 지워버리는 버그가 있었음.
///
/// 지금은 Dart가 직접 DB를 건드리지 않고, Native의 단일 갱신 엔진을 트리거만 함.
/// "필요한지 아닌지"도 Native가 자체 플래그로 판단하므로 중복 호출해도 안전(idempotent)함.
class AlarmRefreshService {
  static final AlarmRefreshService instance = AlarmRefreshService._internal();
  AlarmRefreshService._internal();

  static const _platform = MethodChannel('com.hwani1103.shiftbell/alarm');

  /// 조건 체크 후 필요하면 갱신 (판단은 Native가 함, 중복 호출해도 안전)
  Future<void> refreshIfNeeded() async {
    try {
      await _platform.invokeMethod('triggerGuardCheck');
    } catch (e) {
      print('❌ 알람 갱신 트리거 실패: $e');
    }
  }

  /// 강제 갱신 (조건 체크 없이)
  Future<void> forceRefresh() async {
    try {
      await _platform.invokeMethod('forceNativeRefresh');
    } catch (e) {
      print('❌ 알람 강제 갱신 트리거 실패: $e');
    }
  }
}
