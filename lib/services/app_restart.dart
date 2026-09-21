// lib/services/app_restart.dart
//
// ⭐ 2026-09-14 (출시전 교차 검토 X-03) - 백업 복원 뒤 앱 재시작. 네이티브 "restartApp"(MainActivity.kt)은 프로세스를 끝내므로
// 그 프로세스에서 울리던 알람의 소리·제어·볼륨 복구까지 같이 끊겼음(울림 시간이 긴 알람이 도중에 멈춤). 이 프로세스에서
// 시작된 울림이 있으면 끝날 때까지(끄기·스누즈·자동 종료) 기다린 뒤 재시작한다. 기다리는 동안 호출 화면은 입력을 막고 있어야 함.
//
// ⭐ 2026-09-15 (출시 적합성 재검토 AUD-02) - 여기서의 확인은 "기다리는 중" 안내용일 뿐 최종 판단이 아님.
// 마지막 확인 뒤 ~ 실제 종료 사이(약 900ms)에 새 알람이 울리기 시작하면 예전엔 그대로 끊었음. 이제 네이티브 restartApp이
// 지금 울리는 중이면 false를 돌려주고(여기서 기다렸다 다시 요청), 받아들인 뒤에도 실제 종료 직전에 울림 lock 안에서 다시 확인해
// 그 사이 시작된 울림이 있으면 종료를 미룬다(RingingAlarmTracker.runIfNoLiveRing).

import 'dart:async';

import '../constants/platform_channel.dart';

Future<void> restartAppWhenNoAlarmRinging({void Function()? onWaiting}) async {
  while (true) {
    if (await _alarmRingingLive()) {
      onWaiting?.call();
      await Future<void>.delayed(const Duration(seconds: 2));
      continue;
    }
    // 완료 안내를 잠깐 보여 줌 - 네이티브에도 300ms 지연이 한 번 더 있음
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final accepted = await kAlarmChannel.invokeMethod<bool>('restartApp') ?? true;
    if (accepted) return;
    // 그 사이 울림이 시작됨 - 네이티브가 거절. 울림이 끝날 때까지 기다렸다 다시 요청
    onWaiting?.call();
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}

Future<bool> _alarmRingingLive() async {
  try {
    return await kAlarmChannel.invokeMethod<bool>('isAlarmRingingLive') ?? false;
  } catch (_) {
    // 조회 실패는 "울림 없음"으로 확정하지 않음 - 재시작 요청을 보내면 네이티브 restartApp이 울림 상태를 직접 확인해
    // 울리는 중이면 거절하고, 받아들인 뒤에도 종료 직전에 다시 확인함(AUD-02)
    return false;
  }
}
