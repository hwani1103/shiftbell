# 출시 적합성 재검토 조치 기록 (2026-09-15)

- 대상 검토: [release_readiness_review.md](release_readiness_review.md) (기준 `8354ad4`)
- 조치 기준: `dev` 작업 트리(커밋 전). 코드·자동 테스트만 - **실기기·Play 내부 테스트·Console은 여전히 NOT_RUN**
- 진단 코드 [observed_behavior_test.dart](observed_behavior_test.dart)는 원래 결함을 관찰하는 probe라 그대로 둠
  (AUD-02 probe는 Dart가 여전히 restartApp을 "요청"하므로 계속 관찰 성공으로 나오지만, 이제 네이티브가 울리는 중이면 거절·보류함)

## 조치 요약

| ID | 등급 | 조치 | 위치 | 회귀 테스트 |
|---|---|---|---|---|
| AUD-01 | 높음 | **수정.** 진행창을 `runWithBlockingProgress`로 교체 - `PopScope(canPop:false)`로 뒤로가기 차단, 자기가 띄운 `DialogRoute`만 `removeRoute`(성공·예외 모두), 일괄 변경 중복 실행 플래그. 같은 패턴이던 친구 달력 열기(`friend_open_util.dart`)도 같이 교체 | `lib/utils/blocking_progress.dart`, `calendar_tab.dart` `_bulkAssignShift`, `friend_open_util.dart` | `test/release_audit/g6/recheck_aud_test.dart` AUD-01 2건(뒤로가기 3회 후에도 유지·위에 올라온 route 보존·메인 route 유지 / 예외 시 진행창만 닫고 전달) |
| AUD-02 | 높음 | **수정.** 네이티브 `restartApp`이 울리는 중이면 `false`(Dart가 대기 후 재요청). 받아들인 뒤에도 종료 직전 `RingingAlarmTracker.runIfNoLiveRing`(울림 lock 안에서 확인+종료)으로 다시 판단, 울림이 시작됐으면 2초마다 재확인. 알람 수신 `onReceive`와 종료 Runnable은 같은 메인 스레드라 확인~종료 사이에 `startRing`이 끼어들 수 없음. Dart 조회 실패는 네이티브 최종 판단에 맡김 | `MainActivity.kt` `restartApp`·`scheduleRestartWhenNoLiveRing`, `RingingAlarmTracker.kt`, `lib/services/app_restart.dart` | Kotlin `G6RecheckTest` 2건, Dart AUD-02 2건(거절 → 재요청 / 조회 예외 → 네이티브 판단) |
| AUD-03 | 높음 | **수정.** 지속시간 조회를 `CustomAlarmReceiver.ringDurationMinutes`(스냅샷 → DB → 3분) 하나로 모으고, 수신 때 확정한 값을 오버레이 Intent로 전달. 오버레이는 DB `alarm_types.duration`을 다시 읽지 않음 | `CustomAlarmReceiver.kt`, `AlarmOverlayService.kt` | Kotlin `ringDurationPrefersRestoreSnapshotOverDb` |
| AUD-04 | 높음·실기기 | **코드 미수정 - 실기기 게이트.** foreground service로 재생을 옮기는 것은 Android 14 FGS 유형·Play 신고까지 걸린 설계 변경이라 실기기 근거 없이 출시 직전에 넣지 않음. 실기기에서 끊기면 그때 설계 결정 | - | `device_test_plan.md` A12, 바탕화면 테스트 12·13 |
| AUD-05 | 중간 | **수정.** `currentDateProvider`(자정 타이머 + 앱 재개 시 확인, 날짜가 바뀔 때만 state 변경) 추가. 오늘 판정·OT 7일 조회·주간 요약·수면 슬롯·예측·점수·회복 수면·근무 후 수면 요약이 구독 | `lib/providers/current_date_provider.dart`, `condition_provider.dart`, `sleep_condition_provider.dart` | Dart AUD-05 1건(23:59 → 00:01에 구독 provider만 재계산) |
| AUD-06 | 중간 | **수정.** 시스템 알람 볼륨 변경·복원을 `AlarmStreamVolume`(holder 집합) 한 곳으로. 첫 holder가 잡을 때만 원래 볼륨 저장, 마지막 holder가 놓을 때만 복원 | `AlarmStreamVolume.kt`, `AlarmPlayer.kt`, `MainActivity.kt` 미리듣기 | Kotlin 2건(미리듣기 종료가 실제 알람 중 복원 안 함 / 겹친 알람이 원래 값 안 덮어씀) |
| AUD-07 | 중간 | **수정(부분).** 광고 요청 폭을 `kAppMaxContentWidth`(500dp) 이하로. 실행 중 폭이 줄어 광고가 슬롯보다 넓으면 표시하지 않음(잘린 광고 방지). 폭 변경 시 재요청은 안 함 | `lib/constants/layout_limits.dart`, `ad_service.dart`, `banner_ad_slot.dart`, `main.dart` | 없음(SDK·플랫폼뷰) - 실기기 E2 |
| AUD-08 | 낮음 | **수정.** `analysis_options.yaml`에서 `docs/**` 제외(보관용 재현·진단 코드) | `analysis_options.yaml` | 전체 analyze |

## 남는 한계 (정직하게)

- AUD-02: 알람 브로드캐스트가 이미 전달 대기 중인데 `onReceive`가 시작되기 전에 프로세스가 끝나는 극단적 경계는 OS 브로드캐스트 큐 동작에 달려 있어 코드로 증명하지 못함. 실기기 C4-2로만 확인 가능
- AUD-04: 백그라운드 재생 지속은 여전히 receiver + 싱글턴 `AlarmPlayer` 구조. **실기기에서 끊기면 출시 보류 사유**
- AUD-06: 프로세스가 강제로 회수되면(onDestroy·stopAlarm 미호출) 볼륨 복원이 안 되는 한계는 그대로. "스와이프 종료하면 반드시 복구" 합격 기준은 바탕화면 문서에서 뺌
- AUD-07: 폴더블을 펼친 채 시작해 접으면 광고가 안 보임(자리 높이는 유지). 넓은 화면 지원을 명시할 때 재요청 구현
- 검토 §5 문서 정정 7건은 `g6/device_test_plan.md`와 바탕화면 테스트 문서에 반영

## 검증 (이 작업 트리)

| 항목 | 결과 |
|---|---|
| `flutter analyze` (변경 Dart 파일 12개) | error 0, 새 warning 없음(기존 unused 경고만) |
| `flutter test --no-pub` 전체 | 첫 실행 263/264 - 실패 1건은 새 테스트의 예외 대기 순서(테스트 코드 문제, 제품 코드 무관) → 수정 후 `recheck_aud_test.dart` 재실행 5/5 PASS. 기존 259개는 전부 통과 |
| `gradlew :app:testDevDebugUnitTest --offline` | **80/80 PASS**(기존 75 + `G6RecheckTest` 5), skip·실패·오류 0 - 변경한 Kotlin 소스 컴파일 포함 |
| `flutter build apk --release --flavor dev` | PASS, `build/app/outputs/flutter-apk/app-dev-release.apk`(77.7MB, 2026-09-15 19:07) - 바탕화면 테스트 문서의 새 버전 파일. 기준 HEAD `8354ad4` + 커밋 안 된 이 조치 |
| 실기기 / Play 내부 테스트 / Console | **NOT_RUN** |
