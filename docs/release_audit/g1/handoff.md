# G1 handoff

```text
그룹 / 담당 / worktree / branch: G1 / Claude / C:\Users\Administrator\Desktop\shiftbell-g1 / release/g1
공통 기준 SHA / 최종 소스 SHA: 94ff08f / (미시작)
상태: PLANNED
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

## 진행 기록 (끊김 대비 — 하위 작업마다 한 줄)

| 일시 | 담당 AI | T | 감사 번호 / 하위 작업 | 커밋 SHA | 다음에 할 일 |
|---|---|---|---|---|---|

## 착수 전 인계 메모 (T06 시작 전, Claude)

- **T04-E 케이스 ② 관찰(2026-09-14, 에뮬레이터 API 33):** 업데이트 후 재부팅 → 첫 잠금 해제 전 06:10 알람에서 같은 알람 ID 1의 `CustomAlarmReceiver 알람 수신`이 0.47초 간격으로 **2회**(재생도 2회 시작). 재부팅 없는 케이스 ①은 1회. 추정: `DirectBootReceiver`의 "가장 가까운 알람 즉시 등록"(`scheduleNativeAlarm`)과 `AlarmRefreshEngine.refresh` 재등록이 서로 다른 PendingIntent(extras/flags/requestCode 차이)로 같은 시각에 예약을 2개 만듦. 증거: `scratchpad/t04e/log_case2_after_boot.txt`, `g0/test_results.md` 8장. → **#20(기상 알람 예약 경로 setAlarmClock 통일)·#14/#3(회차) 작업 때 모든 예약 경로의 PendingIntent 동일성 확인·중복 수신 테스트 추가.**
- T11a 기대값: `docs/release_audit/g1/fixtures_draft_p1/` (Codex, contracts §2만 근거) — Dart/Kotlin 공통 계산 테스트 입력으로 사용.
