# G2 테스트 결과

> 기록 항목: 그룹/작업/S 번호, 대상 SHA, flavor/빌드, 기기·API·locale·timezone, 권한/채널/잠금/배터리/네트워크 상태, fixture, 재현 절차, expected/actual, PASS/FAIL/NOT_RUN, 증적 경로, 미검증·잔여 위험 (실행계획 §6.5). 작성자가 스스로 테스트했으면 "작성자 자체 검증"이라고 적는다. 개인정보를 증적에 남기지 않는다.

## T13 — G2 테스트 (Claude, 2026-09-14)

```text
대상: release/g2 4a8f67e (CODE_FROZEN 5cda0e0 + T10 연결 G2-01/02). 테스트 코드 커밋: release/g2 0cbe392 (제품 코드 무변경)
작성·실행: Claude (G2 수정자 Codex와 다른 담당 — 작성자 자체 검증 아님)
환경 F: Windows 10 호스트, Flutter 3.41.7 stable, flutter_test + sqflite_common_ffi(임시 DB) + SharedPreferences mock.
        Firebase 미초기화(firebaseReady=false) — 앱이 오프라인/Firebase 준비 전인 상태와 같은 경로. 기기·flavor 빌드·설치 없음
환경 FS: firebase-tools 15.24.0 Firestore emulator(127.0.0.1:8085), OpenJDK 21, node 24.18, @firebase/rules-unit-testing 4.0.1, firebase JS 11.10.0
        project demo-shiftbell-t13(demo- 전용). 규칙 = release/g2 저장소 firestore.rules. 운영 프로젝트 읽기/쓰기·rules deploy 없음
실기기/Console: 없음 (S9·S12·V5는 아래 NOT_RUN)
```

### 요약

| 구분 | 내용 | 결과 |
|---|---|---|
| F | `test/release_audit/g2/*.dart` 5개 파일 40개 | **40/40 PASS** |
| FS | `test/release_audit/g2/firestore_rules/` 규칙 16개(계약 12 + 현재 동작 관찰 4) | **16/16 PASS** |
| 회귀 | 전체 `flutter test`, `flutter analyze test/release_audit/g2` | 전체 **179/179 PASS**(G2 40 포함), analyze **No issues found** |
| E / S9 | 두 클라이언트 offline·stop·restart·부활 | **NOT_RUN** — 실제 Firebase + 두 기기 필요(T15 사용자) |
| S12 / #29 | 실제 `Firebase.app().options`·appId·DebugView 목적지 | **NOT_RUN** — 실행 앱 + Console(T24 사용자), D8 |
| V5 | 운영 배포 rules와 저장소 rules 일치 | **NOT_RUN** — Console 대조(사용자) |
| S18 / M15 | D7 tombstone rules 상태표·웹 뷰어 revoked | **NOT_APPLICABLE** — D7 rules 미채택(S9 뒤 T16 결정) |

### 감사 번호별 판정

| 번호 | 확인한 것 (PASS) | 실행 못 한 것 | 판정 |
|---|---|---|---|
| #21 | 확인 불가(unavailable) 새로고침이 친구·캐시를 지우지 않고 `unconfirmed` 표시(F-P01·P02·P04), 오프라인 친구 추가는 등록 후 `unconfirmed`(F-P06), 준비 전·잘못된 ownerId 조회를 서버 확인 삭제로 오인하지 않음(F-S14), 깨진 캐시는 data null(F-P05) | 서버 확인 `notFound`/`revoked` → 등록·캐시 제거 경로(Firestore 주입 지점 없음) | **부분 PASS**, 삭제 경로는 S9 |
| #24 | stop 즉시 로컬 off + `stop_pending`·dirty·회차 보존(F-S03), 시작·재개·재연결·복원·재시도·동기화 어느 진입점도 active로 되돌리지 않음(F-S04), stop과 동기화 동시 호출 뒤에도 stop_pending(F-S05), 준비 전 시작은 null·상태 무변경(F-S06), 이름 변경 대기 시 이름 저장·dirty(F-S12), 공유 화면이 stop_pending/active+dirty를 대기로 표시하고 재시도 뒤에도 대기면 토스트(F-W01~05) | 5초 timeout → pending, 늦은 ACK 확정, rejected, 실제 SDK 큐 순서, offline write 중 프로세스 재시작 | **로컬 상태 머신 PASS**, 서버 연동은 S9 |
| #29 | — | S12 전체 | **NOT_RUN** |
| #30 | 서버 확인된 동일 payload 재제출 표시 안 함·map 키 순서 무관·실제 변경만 dirty·정상 수정은 회차 유지(F-S09·S10·S11), refreshAll은 친구 3명이어도 load 1회(F-P02)·2분 스로틀과 force(F-P03), payload 경계(F-D01~09)·공유 코드 경계(F-C01~05), rules 소유권·list 차단·기타 컬렉션·legacy 호환(FS-01~12) | Firestore 실제 read/write 수량 측정(앱이 에뮬레이터에 연결되지 않음 — 친구 수 = refreshAll 1회 read는 코드 기준) | **PASS**(앱 측), 서버 형식·크기 강제는 없음(아래 관찰) |

### 현재 rules 동작 관찰 (FS-OBS — 기대가 아니라 사실 기록, D7 채택 시 거부로 뒤집혀야 하는 행)

| ID | 요청 | 현재 결과 | 의미 |
|---|---|---|---|
| FS-OBS-1 | 소유자가 `ownerName` 숫자·`isRegular` 문자열·임의 필드로 write | 허용 | 서버 자료형 검증 없음(G2 handoff 잔여 위험 3 확인). 앱 `tryFromJson`이 읽기 쪽에서 거부 |
| FS-OBS-2 | `assignedDates` 6000개·`ownerName` 5000자 | 허용 | 서버 크기 제한 없음(1 MiB 문서 한도만). 앱 쓰기는 800KiB·5000개 방어 |
| FS-OBS-3 | generation 3 문서 delete → generation 2 set | 둘 다 허용, 문서 재생성 | 늦은/옛 회차 set으로 공유 부활 가능 — 앱 gate만으로는 막지 못함(잔여 위험 2 확인) |
| FS-OBS-4 | `revoked:true, generation 5` 위에 generation 4 active set | 허용 | tombstone 회차 강제 없음 |

### 테스트 목록

| 파일 | ID | 내용 |
|---|---|---|
| `friend_sync_state_test.dart` (15) | F-S01~S15 | 새 설치 off / legacy enabled → active 회차1 dirty / stop → stop_pending·회차 보존 / 모든 진입점에서 부활 없음 / stop·sync 동시 / 준비 전 시작 null·빈 이름 / active 동기화 pending / off 무변경 / 변경 기반 dedupe / dirty 유지 재시도 / 경계 밖 스케줄 보류 / 이름 변경 대기 / 복원 진입점 / 조회 unavailable / 백업 제외 키 7개 |
| `friend_provider_cache_test.dart` (6) | F-P01~P06 | 캐시 유지·unconfirmed / load 1회 / 스로틀 / 초기 load 대기 / 깨진 캐시 / 친구 추가 |
| `friend_schedule_data_test.dart` (9) | F-D01~D09 | 정상·불규칙 / ownerName 80 / 자료형 / pattern 128·근무명 1..80 / todayIndex·startDate / 색 5000·ARGB / 날짜 키·실재 날짜·5000 / fromJson 예외·캐시 왕복 |
| `friend_share_codec_test.dart` (5) | F-C01~C05 | 왕복 / 공백 / 길이 1..128 / 경로·특수문자·SB1 거부 / 인코딩 예외 |
| `my_share_code_pending_banner_test.dart` (5) | F-W01~W05 | off 안내 없음 / stop_pending 안내·재시도 토스트·상태 유지 / active+dirty 안내 / 반영 완료 안내 없음 / legacy 설치 안내 |
| `firestore_rules/t13_rules.test.mjs` (16) | FS-01~12, FS-OBS-1~4 | 소유자 create·update·delete, 타 uid·미인증 거부, 공개 get·없는 문서 get, list/query 거부, app_config·health_tips·기타 컬렉션·하위 컬렉션, legacy 형식 |

### 테스트 중 확인한 사항

1. **하네스 한정(제품 결함 아님)**: `FriendSyncService` 싱글톤의 직렬 큐 꼬리(`_serialTail`)가 처음 생성된 zone에 묶여, 첫 `testWidgets`의 FakeAsync zone에서 만들어지면 다음 테스트의 재시도가 멈춤. 앱은 zone이 하나라 해당 없음. 위젯 테스트는 `setUpAll`에서 싱글톤을 먼저 만들어 해결. 재시도 버튼이 `scheduleProvider`를 읽어 DB를 여므로 위젯 테스트에도 ffi 임시 DB 필요.
2. **코드 읽기 관찰(재현 안 함, PLAUSIBLE)**: `_submitStop`/`_submitActive`의 큐 작업 안에서 `getOrCreateOwnerId()`(`signInAnonymously`)를 timeout 없이 기다린다. 5초 timeout은 write ACK에만 걸려 있어, 로그인 호출이 실패하지 않고 멈추면 뒤의 stop 제출도 큐에서 대기한다(실행계획 G2 계약 "앞선 대기가 뒤의 stop 제출을 막지 않는다"). 보통 오프라인 익명 로그인은 곧바로 network 오류로 끝나 영향이 작을 것으로 보이나 S9에서 확인 필요. 테스트 단계라 코드 수정 안 함 — T16/G2 재작업 판단 입력.
3. FS 관찰 1~4는 G2 handoff 잔여 위험 2·3과 일치. D7에서 rules 채택 여부를 정할 때 이 표가 뒤집힐 기준이다.

### 사용자·다음 작업으로 넘길 것

- **S9(T15)**: 실제 Firebase에서 두 기기. dev 전용 Firebase 프로젝트가 없어(prod·dev 모두 `shiftbell-29f31`, handoff 잔여 4) 운영 프로젝트 문서를 쓰게 됨 — D8 판단(S12) 전후 순서를 사용자가 정해야 함.
- **서버 ACK·timeout·늦은 ACK 자동 테스트**: 현재 제품 코드에 Firestore/시계 주입 지점이 없어 F로 실행 불가. 주입 지점을 넣으려면 G2 코드 변경(재동결)이 필요 — S9로 대신할지 T16에서 결정.
- **S12·V5(T24)**: Console 확인.

### 재현 명령

```bash
# release/g2 worktree (C:\Users\Administrator\Desktop\shiftbell-g2)
flutter test test/release_audit/g2/
cd test/release_audit/g2/firestore_rules && npm install && npm test   # demo-shiftbell-t13 에뮬레이터만 사용
```

증적: 결과 요약은 이 문서. 원 실행 로그는 세션 임시 폴더(저장소 밖)에만 있고 개인정보 없음.
