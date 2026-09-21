// lib/providers/current_date_provider.dart
//
// ⭐ 2026-09-15 (출시 적합성 재검토 AUD-05) - "오늘" 날짜(시각 없음)를 상태로 둠.
// 컨디션/수면 provider들이 생성 시점의 DateTime.now()만 쓰고 날짜 변경을 구독하지 않아서, 앱을 밤부터 다음 날까지
// 살려 두면(교대근무자에게 흔함) 근무·OT가 안 바뀌는 한 전날 기준 판정과 OT 조회 범위가 캐시에 남았음.
// 자정 타이머 + 앱 재개 때 다시 확인해서 날짜가 바뀌었을 때만 state를 바꿈 → 이걸 watch하는 provider만 재계산.
// (앱이 배경에 있는 동안 타이머가 늦어져도 재개 때 바로잡힘)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 테스트에서 시계를 바꾸기 위한 주입 지점. 앱 코드에서는 건드리지 않는다.
@visibleForTesting
DateTime Function() currentDateClock = DateTime.now;

/// 앱 코드에서 "지금"이 필요할 때(테스트에서 [currentDateClock]을 바꾸면 같이 바뀜)
DateTime appNow() => currentDateClock();

final currentDateProvider = NotifierProvider<CurrentDateNotifier, DateTime>(CurrentDateNotifier.new);

class CurrentDateNotifier extends Notifier<DateTime> {
  Timer? _midnightTimer;
  AppLifecycleListener? _lifecycleListener;

  static DateTime _today() {
    final now = currentDateClock();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  DateTime build() {
    _lifecycleListener?.dispose();
    _lifecycleListener = AppLifecycleListener(onResume: refresh);
    ref.onDispose(() {
      _midnightTimer?.cancel();
      _lifecycleListener?.dispose();
      _lifecycleListener = null;
    });
    final today = _today();
    _scheduleMidnight();
    return today;
  }

  /// 날짜가 바뀌었으면 state 갱신. 자정 타이머·앱 재개에서 호출.
  void refresh() {
    final today = _today();
    if (today != state) state = today;
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    final now = currentDateClock();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    // 1초 여유 - 경계 직전에 깨어나 같은 날짜로 판정하는 것 방지
    _midnightTimer = Timer(nextMidnight.difference(now) + const Duration(seconds: 1), refresh);
  }
}
