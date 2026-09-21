// lib/utils/blocking_progress.dart
//
// ⭐ 2026-09-15 (출시 적합성 재검토 AUD-01) - "로딩 스피너 다이얼로그를 띄우고 작업 → 끝나면 Navigator.pop(context)" 패턴 대체.
// barrierDismissible: false는 배경 터치만 막고 시스템 뒤로가기는 못 막음. 로딩 중 뒤로가기로 스피너가 먼저 닫히면
// 작업 끝의 pop이 스피너가 아니라 그 아래 화면(시트·친구 목록·메인 route)을 닫아 빈 화면이 될 수 있었음.
// 여기서는 (1) 스피너의 뒤로가기를 막고 (2) 이 함수가 띄운 route 객체만 골라 닫음 - 위에 다른 route가 있어도 그대로 둠.

import 'dart:async';

import 'package:flutter/material.dart';

/// [task]가 끝날 때까지(성공·예외 모두) 뒤로가기로 닫히지 않는 진행 표시를 띄우고, 끝나면 그 진행 표시만 닫는다.
/// [task]의 결과를 돌려주고 예외는 그대로 다시 던진다.
Future<T> runWithBlockingProgress<T>(BuildContext context, Future<T> Function() task) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
  unawaited(navigator.push(route));
  try {
    return await task();
  } finally {
    if (navigator.mounted && route.isActive) {
      navigator.removeRoute(route);
    }
  }
}
