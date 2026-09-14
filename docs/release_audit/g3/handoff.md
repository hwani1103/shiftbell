# G3 handoff

```text
그룹 / 담당 / worktree / branch: G3 / Codex / C:\Users\Administrator\Desktop\shiftbell-g3 / release/g3
공통 기준 SHA / 최종 소스 SHA: c0b2e73 / 98c4831
상태: CODE_FROZEN
수정한 감사 번호: #15(M01), #22(M05), #17 수면 부분(M06)
실제 변경 파일(소유권 범위 검사 결과): lib/providers/condition_provider.dart, lib/providers/sleep_record_provider.dart, lib/models/sleep_record.dart, android/app/src/main/kotlin/com/hwani1103/shiftbell/SleepDetectionReceiver.kt, SleepDetectionScheduler.kt, SleepWidgetActionReceiver.kt (G3 소유 6개만)
공통 파일/API/ARB 연결 요청 및 반영 SHA: G1 dataRevision 성공 통지 연결 필요 — g3/integration_requests.md #1. G4 복원 gate 입력 — #2. 반영 SHA 미정
사용자 결정 확인(D 번호·선택·일시): D1~D12 전부 확정(2026-09-14, 실행계획 §4). PROVISIONAL / G0 실기기(T04) 미통과 상속
최종 동작과 회귀 금지 규칙 준수: OT FutureProvider가 overtime revision을 watch하여 성공한 추가·수정·삭제 뒤 DB 최신값을 다시 읽는다. 일정/근무시각 기반 계산은 해당 revision을 의존한다. 자동 수면 후보는 행 start+9h를 기한으로 삼고 Native 예약·종료와 Dart 로드 백스톱 모두 min(now,start+9h), LOW, PENDING_CONFIRMATION을 유지한다. 별도 deadline prefs 없음. 수면 `start_time/end_time`은 Locale.US와 같은 locale 독립 초 단위 고정 형식 사용. G2 소스 및 공유/의학 임계값/DB 스키마 수정 없음.
추가/변경 테스트와 실제 실행 명령: 테스트 코드는 추가하지 않음. 허용된 정적 확인만 수행: git status/diff/show, git diff --check, rg 소유권·호출부 대조.
테스트 결과(실행 빌드·환경·expected/actual·증적): git diff --check PASS. 사용자 병행 예외에 따라 flutter/gradle 빌드, test, pub get, analyze 전부 미실행. 코드 증적은 release/g3 98c4831.
미실행 실기기/Console 항목: T14의 OT 추가·삭제·실패·동일값 재저장 provider fixture와 locale/자정 fixture, S14 화면 꺼진 채 9시간 trigger 및 앱 실행 경로 비교, Doze 지연 확인.
잔여 위험·다음 그룹 주의사항: G1이 성공 뒤에만 revision을 올리는 연결이 반영되기 전에는 #15가 완결되지 않는다. AlarmManager 전달은 Doze/제조사 정책으로 지연될 수 있으나 늦은 trigger도 start+9h를 기록한다. 실제 수면이 9시간을 넘으면 자동 후보가 잘리므로 사용자가 확인 화면에서 수정해야 한다. Dart/Native 동시 백스톱의 DB 경합과 구형 locale 저장값 호환은 T14/S14에서 확인한다. M02 자정·비활성 탭 cache와 M03 DST는 계획대로 보류·조건부 검증이다.
```

## writer 목록 (G4 복원 gate 입력)

| 파일 / 함수 | 쓰는 대상 | 트리거 | 실행 컨텍스트 | T08 변화 |
|---|---|---|---|---|
| `lib/providers/sleep_record_provider.dart` `SleepRecordNotifier._load` | DB `sleep_records` 만료 AUTO 후보의 `end_time/confidence/updated_at` | provider 최초 생성, 명시 refresh, 컨디션 탭 resume | Flutter isolate / sqflite | start+9h 만료 백스톱 writer 추가 |
| 같은 파일 `addManual/confirmPending/discardPending/updateTimes/deleteRecord` | DB `sleep_records` insert/update/delete | 앱 수면 UI 사용자 동작 | Flutter isolate / sqflite | 기존 writer, gate 전수 목록에 포함 |
| 같은 파일 `_notifyAutoRejection` → Native `recordSleepAutoRejection` | DP prefs `sleep_detection_state`의 `reject_hour_count_<h>`, `reject_hour_last_at_<h>` | AUTO 후보 거부·삭제 | Flutter MethodChannel → Android main process | 기존 writer |
| `SleepDetectionReceiver.handle` | DB `sleep_records` insert/update/delete, DP prefs `first_off_sample_at` | 20분/9시간 AlarmManager, Guard, boot, 앱 resume의 `checkNow` | BroadcastReceiver 또는 앱이 띄운 background thread | 화면 꺼짐 9시간 종료 update 추가 |
| `SleepDetectionReceiver.recordRejection` | 위 DP prefs 거부 학습 키 | Flutter 거부 통지 | Android main process | 기존 writer |
| `SleepDetectionScheduler.ensureScheduled/cancel` | OS AlarmManager의 수면 감지 PendingIntent | 모든 `checkNow` 종료, boot/앱 경로 | Android main process | 진행 행 deadline 기반 예약 trigger 추가 |
| `SleepWidgetActionReceiver.onReceive/finishOngoing` | DB `sleep_records` insert/update/delete, OS 위젯 갱신 | 홈 위젯 취침/기상 | BroadcastReceiver | 기존 writer; 저장/파싱 locale만 US로 고정 |

새 prefs 키, DB 테이블·컬럼, MethodChannel API는 추가하지 않았다.

## 진행 기록 (끊김 대비 — 하위 작업마다 한 줄)

| 일시 | 담당 AI | T | 감사 번호 / 하위 작업 | 커밋 SHA | 다음에 할 일 |
|---|---|---|---|---|---|
| 2026-09-14 | Codex | T08 | #15 OT revision 소비, #22 9시간 후보 종료, #17 수면 locale 고정 — CODE_FROZEN | `98c4831` | T10에서 G1 revision 연결 후 T14/S14 검증 |
