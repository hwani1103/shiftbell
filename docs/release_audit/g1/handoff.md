# G1 handoff

```text
그룹 / 담당 / worktree / branch: G1 / Claude / C:\Users\Administrator\Desktop\shiftbell-g1 / release/g1
공통 기준 SHA / 최종 소스 SHA: 94ff08f / (미시작)
상태: CODING (2026-09-14 T06 시작)
수정한 감사 번호:
실제 변경 파일(소유권 범위 검사 결과):
공통 파일/API/ARB 연결 요청 및 반영 SHA:
사용자 결정 확인(D 번호·선택·일시): D1~D12 전부 확정(2026-09-14, 실행계획 §4). PROVISIONAL / G0 실기기(T04) 미통과 상속
최종 동작과 회귀 금지 규칙 준수:
추가/변경 테스트와 실제 실행 명령:
테스트 결과(실행 빌드·환경·expected/actual·증적):
미실행 실기기/Console 항목:
잔여 위험·다음 그룹 주의사항:
```

## 착수 전 인계 메모 (T06 시작 전, Claude)

- **T04-E 케이스 ② 관찰(2026-09-14, 에뮬레이터 API 33):** 업데이트 후 재부팅 → 첫 잠금 해제 전 06:10 알람에서 같은 알람 ID 1의 `CustomAlarmReceiver 알람 수신`이 0.47초 간격으로 **2회**(재생도 2회 시작). 재부팅 없는 케이스 ①은 1회. 추정: `DirectBootReceiver`의 "가장 가까운 알람 즉시 등록"(`scheduleNativeAlarm`)과 `AlarmRefreshEngine.refresh` 재등록이 서로 다른 PendingIntent(extras/flags/requestCode 차이)로 같은 시각에 예약을 2개 만듦. 증거: `scratchpad/t04e/log_case2_after_boot.txt`, `g0/test_results.md` 8장. → **#20(기상 알람 예약 경로 setAlarmClock 통일)·#14/#3(회차) 작업 때 모든 예약 경로의 PendingIntent 동일성 확인·중복 수신 테스트 추가.**
- T11a 기대값: `docs/release_audit/g1/fixtures_draft_p1/` (Codex, contracts §2만 근거) — Dart/Kotlin 공통 계산 테스트 입력으로 사용.

## 진행 기록 (끊김 대비 — 하위 작업마다 한 줄)

| 일시 | 담당 AI | T | 감사 번호 / 하위 작업 | 커밋 SHA | 다음에 할 일 |
|---|---|---|---|---|---|
| 2026-09-14 | Claude | T06 | 착수: 기준 94ff08f, g1 pub get 완료. 첫 묶음 #3·#14·#23 코드 읽기 완료. **원인** #3 종료 타이머가 Activity/Overlay Handler에만 있어 홈 이동 시 소실, 트래커가 ID만 저장(회차 없음) / #14 isAlarmRinging=MediaPlayer.isPlaying 전역 bool(ID 무시, 진동·무음 false) / #23 MediaPlayer().apply 중간 실패 시 미해제. **설계** RingingAlarmTracker에 누적 ring_counter + active(ID,회차) + 메모리 토큰 폴백(commit 실패) · CustomAlarmReceiver가 울림 시 회차 담은 AlarmManager 종료 예약(AlarmActionReceiver ACTION_RING_TIMEOUT) · 종료/버튼은 회차 일치 시만 · 화면/오버레이 타이머는 토큰 보호한 채 유지(S4 전 제거 금지) · isAlarmRinging(alarmId) = tracker 기준 · MediaPlayer 로컬 소유 후 성공 시만 필드 대입 | - | Dart alarm_provider 삭제 흐름·MainActivity 핸들러 확인 → 구현 |
| 2026-09-14 | Claude | T06 | **#3·#14·#23 구현 완료(WIP).** #3: `RingingAlarmTracker` 누적 `ring_counter` + 활성(ID,회차), lock 직렬화, commit+1회 재시도 실패 시 메모리 회차 유지(ID 단독 비교 없음), 이전 버전 ID-only 값은 회차 0. 모든 종료 경로(Activity/Overlay 버튼·타이머, 7777 끄기, 인계, 종료 예약)가 소리/DB 전에 `AlarmActionHelper.claimRingEnd(ID,회차)` 통과. `CustomAlarmReceiver`가 울릴 때 `ACTION_RING_TIMEOUT`(data `shiftbell://ring-timeout/ID/회차`) exact 예약(권한 없으면 비정확 대체), 화면·오버레이 타이머는 토큰 보호로 유지(S4 후 제거 판단), 지난 회차 화면 요청은 즉시 닫음, 같은 ID 중복 수신은 이전 회차 예약 회수 후 새 회차. `finishUp`의 ID 기준 추적 해제 제거. #14: MethodChannel `isAlarmRinging(alarmId)`=활성 회차 ID 비교(진동·무음 포함), 신규 `stopRingingAlarm(alarmId)`=판정+종료 원자화 → Dart `deleteAlarm`이 반환값으로 swiped/cancelled_before_ring 결정, calendar_tab/next_alarm_tab의 선행 `dismissOverlay` 제거(선행 시 이력 오판). 부수 수정: 오버레이 외부 종료 신호가 새 알람 재생 뒤 도착해 새 소리를 끄던 경로 차단(활성일 때만 stop). #23: `startLoopingPlayer` 지역 생성·실패 시 release·성공 후 대입, `AlarmPlayer.isAlarmRinging()` 제거. **테스트** `G1RingRoundTest` 10건 + 기존 23건 = Kotlin 33/33 PASS(`sh ./gradlew testDevDebugUnitTest`, Robolectric SDK34). flutter analyze(변경 3파일) 신규 경고 0. **신규 Native 키(등록부 반영 요청)**: `alarm_state.currently_ringing_round`(long, G1, 백업 안 됨, 없으면 회차 0), `alarm_state.ring_counter`(long, G1, 백업 안 됨, 절대 초기화 안 함). **미검증**: 화면/오버레이 실제 동작·홈/잠금/Doze 지속시간·진동/무음 삭제 = S4 실기기. Dart deleteAlarm 단위 테스트 없음. **수정 전 FAIL 확인**: `AlarmPlayer.kt`만 94ff08f로 되돌려 G1RingRoundTest 실행 → `#23 재생 준비 실패 해제` FAIL(`expected:<END> but was:<IDLE>`), 복원 후 PASS. #3/#14 테스트는 수정 전 API가 없어 컴파일 단계에서 성립 안 함(동작 비교는 S4) | `97c72fc` | #4/#13 착수 |
