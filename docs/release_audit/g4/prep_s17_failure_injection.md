# S17 복원 경합·실패 주입 테스트 설계 초안

> T09 문서 초안이다. 제품 코드와 테스트 코드를 수정하거나 실행하지 않았다. T18 G4 CODE_FROZEN SHA에 맞춰 seam 이름을 갱신한 뒤 T19에서 구현·실행한다.

## 검증할 복원 상태 기계

`validated → locked → os_cleared → db_applied → prefs_applied → os_reconciled → 완료 정리`

각 단계는 영속 작업 ID, 입력 사본 hash, 단계 값, ID 매핑을 가져야 한다. 프로세스가 어느 줄에서 끝나도 같은 사본과 매핑으로 재실행되어야 한다. DB·prefs·OS 전체를 하나의 transaction처럼 판정하지 않는다.

## 기준 fixture

| 영역 | 시작 상태 |
|---|---|
| 현재 기기 DB | 현재 울리는 fixed 1개, 미래 snoozed 1개, 미래 custom 1개, fixed 여러 개, 일정 알림 on/off 각 1개, 종료 전 AUTO 수면 후보 1개 |
| 현재 런타임 | activeRing ID와 회차 token, snooze PendingIntent, Guard, 일정 알림, 수면 감지 예약, 일부 표시 Notification |
| 백업 | 충돌하는 custom ID, 규칙/불규칙 근무표 각각 fixture, alarms 제외 원본, alarm_overrides skip/set_type, 수면 null end_time, 친구 캐시, 영구 이력 |
| prefs | 일반 설정, 권한/튜토리얼/업데이트/백업 휘발 키, G2 active 또는 stop_pending 공유 상태 |
| 파일 | 정상 직전 백업 A, 새 입력 B, 손상/미지원/사본 hash 불일치 변형 |

기대 ID 정책은 현재 activeRing·snoozed가 원 ID를 유지하고, 충돌하는 **백업 custom**만 새 ID를 받는 것이다. 첫 시도의 `{백업ID: 새ID}`를 DP 작업 상태에 기록하고 재시도에서 재사용한다.

## 주입 지점과 기대 결과

| 주입 ID | 실패·중단 위치 | 즉시 기대 | 재시작·재시도 기대 |
|---|---|---|---|
| FI-01 | 파일 열기/JSON decode/버전·형·테이블·컬럼·참조 검증 | DB/prefs/OS 무변경, lock 미획득 | 오류 원인 표시 후 다른 파일 선택 가능 |
| FI-02 | DP 작업 사본 쓰기 또는 fsync/hash 확인 | 원본과 현재 상태 무변경 | 불완전 사본 후보 제외, 다시 복사 가능 |
| FI-03 | lock prefs 기록 전/후, 메모리 owner 생성 전/후 | 반쪽 owner를 성공으로 보지 않음 | 메모리 token 없는 죽은 작업 판정 후 현재 DB 예약 복구와 미완료 안내 |
| FI-04 | 옛 OS 예약 취소 도중 N번째 | 현재 울림·snooze 보호, 취소 결과를 단계 완료로 기록하지 않음 | 현재 DB 기준 안전 reconcile 후 같은 작업 재개 |
| FI-05 | DB transaction 첫/중간 write | transaction 전체 rollback, 이력/sequence/현재 행 불변 | 같은 사본·ID 매핑으로 재실행 |
| FI-06 | DB commit 성공 직후 `db_applied` 단계 기록 전 crash | DB는 적용됐지만 단계가 이전 값 | 재실행이 중복 행/이력/ID 변경 없이 이미 적용된 결과를 인식하거나 멱등 재적용 |
| FI-07 | prefs N번째 setter false/throw | DB 적용 상태와 prefs 미완료를 구분, 완료 표시 금지 | `db_applied`에서 이어서 남은 prefs를 결정적으로 적용 |
| FI-08 | prefs 완료 직후 단계 기록 전 crash | 같은 prefs setter 재호출 가능 | 공유 제외키·현재 기기 상태가 덮이지 않고 멱등 |
| FI-09 | fixed 재생성/미래 custom/snoozed/일정 알림 N번째 OS 예약 실패 | `os_reconciled` 미기록, 어떤 예약이 남았는지 관찰 가능 | 현재 DB와 보호 snapshot 기준 전체 명시 reconcile, 중복 PendingIntent 없음 |
| FI-10 | owner 최종 reconcile이 일반 gate에 막힘 | timeout 성공 처리 금지, 교착 증적 | owner token 경로로만 통과하여 완료 가능 |
| FI-11 | 완료 상태 기록 뒤 작업 사본/lock 정리 실패 | 복원 데이터는 성공, 정리 잔여를 별도 상태로 기록 | 다음 시작에서 완료된 작업을 다시 적용하지 않고 안전 정리 |
| FI-12 | 각 단계의 Future 취소/예외, 앱 background/kill | `finally`만 믿어 성공 표시하지 않음 | 영속 단계에서 이어감; 살아 있는 owner는 시간만으로 탈취하지 않음 |

## 경합 행렬

| 경합 writer | 주입 시점 | 기대 |
|---|---|---|
| 알람 refresh/Guard/timezone/boot | locked~os_reconciled | 실행 연기, pending 1회. owner 완료 뒤 최신 DB로 1회 reconcile |
| 현재 알람 dismiss | DB 교체 직전·중·직후 | 허용. SQLite 직렬화 뒤 최종 결과에 반영되고 activeRing/Notification 정리 |
| 현재 알람 snooze | DB 교체 직전·중·직후 | 허용. 원 ID, 소리/볼륨/진동/duration snapshot, 다음 PendingIntent 보존 |
| 알람 timeout | 모든 단계 | dismiss와 같은 허용 정책, 이력 1회 |
| 수면 감지 20분/9시간 receiver | locked~완료 | DB write와 다음 예약 연기. 완료 후 진행 행에서 deadline 재계산 |
| 수면 위젯 취침/기상 | locked~완료 | 입력 유실 금지 정책을 구현에 맞춰 검증; 중간 DB 직접 write 금지 |
| 일정 알림 CRUD/receiver/재예약 | locked~완료 | UI write와 재예약 연기; 이미 울리는 단순 표시 제어는 별도 판정 |
| 자동백업 background trigger | locked~완료 | 실행 안 함, dirty/pending 유지. 복원 중간 snapshot 파일 생성 금지 |
| 일반 앱 DB/prefs UI 저장 | locked~완료 | 차단 안내 또는 재시도 가능 pending; 성공 toast 금지 |
| G2 late Firestore ACK·retry | locked~완료 | 백업 공유키를 적용하지 않음. 최신 intent/generation 일치 결과만 반영, restore 완료 뒤 현재 payload 재시도 |

## 데이터 무결성 assertion

- 검증 실패와 사본 실패에서는 DB checksum, 모든 prefs, OS 예약 집합이 시작값과 같다.
- `alarm_history`와 `alarm_creation_log`는 삭제하지 않고 자연키로 중복 제외 병합한다.
- 구버전 백업에 없는 원본 테이블은 버전별 기본/빈 상태가 되며 기존 값이 몰래 남지 않는다. 영구 이력만 예외다.
- null `sleep_records.end_time`과 불규칙 모드 빈 pattern은 조건에 맞으면 유효하다.
- 명시 ID 삽입 뒤 `sqlite_sequence`와 다음 신규 ID가 이월/백업 ID와 충돌하지 않는다.
- activeRing/snoozed의 alarm type이 복원 뒤 없어도 snapshot으로 재생·duration 조회가 가능하고 UI가 crash하지 않는다.
- `alarm_overrides`의 자료형/CHECK/참조/고유키를 검증하며 없는 구버전 백업은 기존 override를 비운다.
- G2 공유 7키는 export/import에서 빠지고 신규 설치는 off, 기존 active/stop_pending은 현재 UID·generation을 유지한다.
- 완료 뒤 fixed, 미래 custom, 미래 snoozed, 일정 알림, Guard, 수면 감지의 DB 기대 집합과 실제 PendingIntent 집합이 일치한다.

## 자동화 seam 제안

G4 구현은 단계 저장소, DB 적용기, prefs 적용기, OS 취소/예약기, 파일 사본 저장기를 interface로 분리하거나 주입 가능한 callback을 둔다. 각 seam에 `before`, `after side effect`, `after durable phase write` failpoint를 둬야 commit과 단계 기록 사이 crash를 재현할 수 있다. 테스트 전용 failpoint는 release 경로에서 활성화될 수 없어야 한다.

T19은 실제 임시 SQLite와 가짜 prefs/OS 기록기를 함께 사용한다. 단순 mock 호출 순서만으로 PASS하지 않는다. T20 실기기에서는 울리는 알람·스누즈·프로세스 kill·재시작·MediaStore 파일을 실제로 확인한다.

## 결과 기록 형식

각 케이스에 대상 SHA, API/OS, 시작 fixture hash, failpoint, crash 여부, 재시도 횟수, 단계 before/after, DB/prefs/OS expected와 actual, ID mapping, 파일 URI/hash, logcat 또는 테스트 로그 위치를 남긴다. 자동화 PASS와 실기기 NOT_RUN을 한 상태로 합치지 않는다.
