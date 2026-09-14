// lib/services/app_restart.dart
//
// ⭐ 2026-09-14 (출시전 교차 검토 X-03) - 백업 복원 뒤 앱 재시작. 네이티브 "restartApp"(MainActivity.kt)은 프로세스를 끝내므로
// 그 프로세스에서 울리던 알람의 소리·제어·볼륨 복구까지 같이 끊겼음(울림 시간이 긴 알람이 도중에 멈춤). 이 프로세스에서
// 시작된 울림이 있으면 끝날 때까지(끄기·스누즈·자동 종료) 기다린 뒤 재시작한다. 기다리는 동안 호출 화면은 입력을 막고 있어야 함.

import 'dart:async';

import '../constants/platform_channel.dart';

Future<void> restartAppWhenNoAlarmRinging({void Function()? onWaiting}) async {
  while (await _alarmRingingLive()) {
    onWaiting?.call();
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  // 완료 안내를 잠깐 보여 줌 - 네이티브에도 300ms 지연이 한 번 더 있음
  await Future<void>.delayed(const Duration(milliseconds: 600));
  await kAlarmChannel.invokeMethod('restartApp');
}

Future<bool> _alarmRingingLive() async {
  try {
    return await kAlarmChannel.invokeMethod<bool>('isAlarmRingingLive') ?? false;
  } catch (_) {
    return false;
  }
}
