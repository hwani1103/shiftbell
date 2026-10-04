# 갤럭시 워치·플립8 커버 알람 검토

## 최종 상태: 워치 기능 제거

2026-09-30 사용자 요구는 별도 워치 앱 설치 없이 최소 5회 진동과 휴대폰에서 필요한 Wearable 설정 화면으로 직접 연결하는 흐름이다. 알림 브리지만으로 이 조건을 안정적으로 보장할 수 없어 사용자 지시에 따라 워치 모듈, Data Layer 연결, 추가 미러링 알림과 전용 테스트를 제거했다. 아래는 폐기한 실험의 기록이며 현재 기능이나 설치 안내가 아니다. 기존 워치 테스트 APK는 사용하지 않는다. 공유 달력 작업과 플립 검토는 별도 기록을 따른다.

## 후속: 워치 구현 승인 및 테스트 빌드

사용자가 워치 구현을 추가 요청하여 `android/wear`와 휴대폰 `WatchAlarmBridge`를 구현했다. 아래 내용은 구현 전 검토 기록이다. 플립은 여전히 검토만 유지한다.

Wear OS 3/API30 이상(Watch4 이후)의 전용 화면, OS 진동 알림과 +5m/끄기, 같은 패키지·서명 Data Layer 통신을 사용한다. 직접 연결된 노드만 허용하며 영구 명령 큐는 없다. 세션/회차/요청 만료를 검증하고 휴대폰의 기존 메인 루퍼 제어 경로로 처리하며 ACK 전에는 성공으로 표시하지 않는다. 종료·연결 해제·재부팅 후 상태가 만료되도록 했다.

전용 화면은 검정 바탕과 인디고 버튼, 교대시계·시각·근무명·두 버튼으로 구성한다. 작은 화면의 큰 글자에서는 근무명을 생략한다. 8개 원형 크기/배율 조합 렌더링을 검사했다. 실제 워치 진동·Bluetooth 연결 검증은 아직 하지 않았다. 전달 파일과 실기기 절차는 `build/watch_review_2026-09-30/테스트안내.txt`에 있다.

공식 [Wear OS 알림 문서](https://developer.android.com/training/wearables/notifications)는 full-screen intent를 지원하지 않는다고 명시한다. 따라서 이 구현은 **진동 알림의 직접 액션 또는 알림 탭 후 전용 화면** 방식이며 화면 강제 전환·지속 진동은 제공하지 않는다. 진동은 사용자 알림/DND 설정을 따른다.

## 갤럭시 워치: 구현 가능, 현재 앱은 전달하지 않는 상태

범위는 Wear OS 기반 Galaxy Watch(Watch4 이후)와 안드로이드 폰의 블루투스 연결 환경이다. 구형 Tizen 워치는 별도 검토가 필요하다.

현재 `NotificationHelper.showRingControlNotification()`은 알림 7777에 5분 후/끄기 PendingIntent를 이미 넣는다. 그러나 `setLocalOnly(true)`, `setOngoing(true)`, `setSilent(true)`를 사용하고 채널 진동도 꺼져 있다. 특히 앞의 두 설정은 공식 문서가 명시한 워치 알림 브리징 제외 조건이다. 폰에서 `AlarmPlayer`가 만드는 소리·진동이 워치로 자동 전달되는 것도 아니다.

근거: [Android Wear 알림 브리징](https://developer.android.com/training/wearables/notifications/bridger), [Wear 알림 동작과 액션](https://developer.android.com/training/wearables/notifications).

요청한 화면은 구현 가능하다.

```text
교대시계 알람
07:00
[+5m] [끄기]
```

가능한 두 범위:

| 방식 | 가능한 수준 | 한계 |
|---|---|---|
| 별도 워치 전달용 알림 | 제목/시각과 두 액션을 OS 알림 UI로 보여 주는 작은 시제품 | 워치 설정·OS 정책에 따른 진동, 표시 지연, 배치 차이. 지속 진동과 정확히 고정된 화면은 보장할 수 없음 |
| 작은 Wear OS 동반 앱 | 워치에서 진동과 전용 화면을 관리하고 두 요청을 폰으로 전달 | 워치 앱 설치·배포와 연결/해제/중복 요청 처리 필요 |

요청한 전용 화면과 진동 제어까지 목표라면 후자가 적합하다. 폰이 알람의 최종 상태를 소유하고, 워치는 `alarmId + ringRound + action + requestId`를 보내며 폰의 확인 응답을 받은 뒤 처리 완료를 표시하는 구조를 권한다. 기존 `AlarmActionHelper`의 회차 검증을 그대로 통과시켜 이전 알림/중복 탭이 다음 알람을 끄지 않도록 한다. 스와이프로 알림만 치우는 동작을 곧바로 알람 끄기로 연결하지 않는 것도 필요하다.

블루투스 환경에서는 인터넷 서버가 필수는 아니다. 다만 Wear Data Layer 자체가 Bluetooth 전용 전송 API는 아니다. `isNearby`로 직접 연결 기기를 확인하고, 직접 연결이 끊기면 동작 불가를 표시하는 범위로 설계해야 한다. Wi-Fi/LTE를 끈 실제 기기에서 연결·해제 시나리오를 확인하기 전에는 엄격한 Bluetooth-only 보장을 주장하면 안 된다. `MessageClient`는 자동 재시도 없는 best-effort이므로 확인 응답과 짧은 만료 시간이 필요하다. 연결이 끊어진 동안 쌓아 둔 ‘끄기’를 나중에 실행해서는 안 된다.

근거: [연결된 기기 탐색](https://developer.android.com/training/wearables/data/discover-devices), [MessageClient와 다른 전송 수단 비교](https://developer.android.com/training/wearables/data/client-types), [Node.isNearby](https://developers.google.com/android/reference/com/google/android/gms/wearable/Node).

## 플립8: 소리·진동 경로와 커버 조작 가능 여부는 별개

현재 `CustomAlarmReceiver`는 `AlarmPlayer.playAlarmFromDB()`로 소리/진동을 시작한 다음 제어 알림과 UI를 띄운다. 접힘 여부 때문에 재생을 생략하는 분기는 없다. 따라서 코드 구조상 폴딩 자체가 알람 재생을 막지는 않을 것으로 예상한다. **플립8 실기기에서 확인한 결과는 아니다.**

반면 화면은 현재 잠금 여부로 `AlarmActivity`/오버레이 경로를 선택한다. 커버 display로 보내는 별도 분기나 FlexWindow 전용 위젯 등록은 없다. 커버 화면은 단순히 작은 일반 잠금화면과 같지 않으며, 폰을 접었다고 Android의 keyguard 상태가 항상 같은 것도 아니다. 이미 있는 full-screen intent만으로 삼성 커버 화면에 전체화면과 두 버튼이 자동 표시된다고 단정할 수 없다.

[Android의 시간 민감 알림](https://developer.android.com/develop/ui/views/notifications/time-sensitive)은 잠금/사용 중 상태의 일반 동작을 설명하지만 삼성 커버 화면의 지원 보장은 아니다. [삼성 Flip8 안내](https://www.samsung.com/us/support/answer/ANS10013200/)도 커버에서 알림을 볼 수 있고 지원 앱을 실행할 수 있다고 설명하며, 모든 앱을 지원한다고 하지는 않는다.

정리하면:

- 소리/진동을 내기 위해 커버 위젯이 반드시 필요한 것은 아니다. 이미 알람 재생 경로가 있다.
- 현재 알림에 5분 후/끄기 액션이 있지만, 접힌 잠금 상태의 커버에서 둘이 노출되고 실제 전달되는지는 미확인이다.
- 커버 위젯은 조작 화면을 추가하는 수단이다. 위젯을 만들었다는 사실만으로 알람 발생 시 자동으로 커버를 켜고 전면 표시하는 문제까지 해결되지는 않는다.
- 삼성의 [Flex Window 위젯 개발 문서](https://developer.samsung.com/galaxy-z/flex_window.html)는 `com.samsung.android.appwidget.provider`와 `display="sub_screen"` 메타데이터를 소개한다. Flip5 기준 문서이므로 Flip8/해당 One UI에서 같은 지원 범위를 직접 확인해야 한다.

구현 전에 Flip8에서 확인할 최소 항목은 접힌 상태의 잠금/해제/AOD/화면 꺼짐 각각에서 ① 소리·진동 ② 커버 알림/화면 자동 노출 ③ 끄기 ④ +5분 ⑤ 열고 닫은 뒤 제어 상태 유지다. 전체화면 알림 허용과 커버 알림 설정을 함께 기록해야 한다. 이 검토에서는 네이티브 알람 코드나 기존 알림 설정을 변경하지 않았다.
