# G0 테스트 결과 (T03)

> 기록 항목: 실행계획 §6.5. 작성: Claude, 2026-09-14. **최종 — T03 자동 테스트 범위 PASS (REPAIR-REJECT는 사용자 결정 A로 수용), 실기기 S1은 T04**

## 1. 대상과 환경

| 항목 | 값 |
|---|---|
| 제품 코드 (동결) | `release/g0` — T02 동결 `cf7421b` → **T03 중 컴파일 결함 수정 후 재동결 `637b56a`** (4장 #1) |
| 테스트 코드 | `61a162c`(기반) + `c06ffea`(Kotlin 환경 차이 반영). 최종 테스트 실행 대상 HEAD `c06ffea` |
| worktree | `C:\Users\Administrator\Desktop\shiftbell-g0` |
| 호스트 | Windows 10, RAM 5.9GB. 빌드·테스트는 한 번에 하나, Flutter 실행 전 Gradle 데몬 종료 |
| Flutter/Dart 테스트 | `flutter test` + `sqflite_common_ffi`(실제 SQLite, dev_dependency 추가) |
| Kotlin 테스트 | `sh ./gradlew :app:testDevDebugUnitTest --max-workers=1`, Robolectric 4.14.1(SDK 34 고정), **Robolectric SQLite 3.8.7** |
| fixture 원본 | T01(Codex) `docs/release_audit/g0/fixtures_draft` → `test/release_audit/g0/fixtures_src` (LF 정규화 복사) |
| 에뮬레이터 / 실기기 | 사용 안 함 (5장 NOT_RUN) |

실행 명령:
```
python tool/g0/build_fixtures.py --import-from <T01 fixtures_draft>   # fixture·기대값 빌드
G0_UPDATE_SNAPSHOT=1 flutter test test/release_audit/g0/db_reference_schema_test.dart   # 기준 구조 생성(1회)
cd android && sh ./gradlew :app:testDevDebugUnitTest --max-workers=1 && sh ./gradlew --stop
cd .. && flutter test
```

## 2. fixture 사전 점검

- Python sqlite3 3.40.1로 23개 SQL 실행: user_version, 입력 행 수(manifest `input_rows`), `integrity_check` 모두 일치.
- **SHA256은 원본 바이트 그대로는 23개 전부 불일치, LF로 정규화하면 23개 전부 일치.** 디스크 저장 시 CRLF로 바뀐 것이며 내용 차이 아님. 빌더는 LF 기준으로 검증.
- 빌더(`tool/g0/build_fixtures.py`)는 G0 구현(`migrations.json`, 실행기)을 읽지 않고, T01 `expected.md` 규칙 + manifest 입력 행으로 v24 기대 데이터를 계산.
- 기준 구조 `v24_oncreate_schema.json` = 실제 `DatabaseService` 신규 설치(`_onCreate`) DB의 PRAGMA 스냅샷(테이블·컬럼 이름/타입/NOT NULL/기본값/PK, 인덱스 UNIQUE·생성원인·부분·컬럼 순서, FK).
- 음성 대조(Dart): fixture 23개 확인, 값 하나 바꾼 기대값·행 하나 뺀 기대값·v17 구조를 비교기가 불일치로 잡음 → 통과가 헛돌지 않음.

## 3. 결과

**Flutter `flutter test` 전체 139/139 PASS** (G0 37 + 기존). **Kotlin `testDevDebugUnitTest` 23/23 PASS** (G0 13 + 기존 10).

| 케이스 (T01 expected.md) | Dart (ffi) | Native (Robolectric) | 비고 |
|---|---|---|---|
| MIG-ALL v1~v23 → v24: 기대 데이터 + 기준 구조 | PASS | PASS | Dart는 제품 openDatabase 옵션 복제 경로 |
| REOPEN (두 번째 open 데이터 변화 0) | PASS | PASS | 23개 전부 |
| SERVICE v18 / v12 (실제 `DatabaseService` 경로) | PASS / PASS | — | |
| 자산 경로 (Native가 `flutter_assets/assets/db/migrations.json`을 읽어 저장소 원본과 동일, 무주입 v18→v24) | — | PASS | **debug merge 기준.** release APK·잠금 해제 전은 S1 |
| ROLLBACK v12, v20에 실패 주입 | PASS | PASS | 스키마·데이터·user_version 원상, 원인 제거 후 성공 |
| FRIEND-ROLLBACK v16, v17 DROP·CREATE 뒤 실패 | PASS | PASS | 옛 friends 스키마·701 복원 |
| MISSING-COLUMN (v23에서 컬럼·인덱스 제거 + v24 표기) | PASS | PASS | repair 5건(컬럼·인덱스·alarm_overrides+인덱스 2) 후 기준 구조와 동일, 데이터 보존 |
| ALTER-FAIL repair (NOT NULL 기본값 없는 ALTER) | PASS | PASS | 예외 전파, 같은 트랜잭션의 CREATE TABLE도 롤백 |
| ALTER-FAIL migration (없는 테이블) | PASS | PASS | 건너뛰지 않고 실패, 버전 유지 |
| FUTURE-VERSION 25 | PASS | PASS | Dart 예외 / Native 게이트 스킵 + 직접 open 시 onDowngrade 예외, 버전·데이터 무변경 |
| VERSION-ZERO (파일 있음·테이블 0·버전 0) | — | PASS | 게이트 스킵, 직접 open 시 onCreate 예외, 스키마 생성 없음 |
| NATIVE-NEW (파일 없음) | — | PASS | null 반환, 파일 생성 안 함 |
| onUpgrade 잠금 후 버전 재확인 | — | PASS | 이미 목표면 변화 0, 더 높으면 예외 |
| REPAIR-WHITELIST 등 파싱 규칙 20케이스 (공유 JSON) | PASS 20/20 | PASS 20/20 | DROP/UPDATE/DELETE/RENAME/INSERT/DROP COLUMN/두 문장/순서/대상 누락 거부 등 |
| alarm_overrides 제약 (UNIQUE 슬롯 키 + G0 CHECK 3종 + NOT NULL) | PASS | PASS | 신규 설치 DB + 23개 마이그레이션 DB, 확인 행 롤백 |
| V4 StartupGate (성공 / 실패→재시도 / 지연 표시·중복 실행 없음 / 반복 실패 / 원문 표시 조건) | PASS 5/5 | — | |
| 기존 테스트 회귀 | PASS (Flutter 기존 전부) | PASS (AlarmDayOffsetPriority 3, H2 2, ScheduleNotificationScheduler 5) | H2는 fixture 준비 방식 교체 |
| **REPAIR-REJECT** (v17 전환 없이 v24로 찍힌 옛 friends DB) | 관찰: 오류 없이 열림 | 관찰: 오류 없이 열림 | 부분 충족 → **사용자 결정 A(유지), ACCEPTED_RISK** (6장) |

## 4. T03 중 발견 → 조치 이력

| # | 발견 | 분류 | 조치 |
|---|---|---|---|
| 1 | `DatabaseHelper.kt:143` `"v$newVersion으로"` — Kotlin이 한글을 식별자 문자로 읽어 **컴파일 실패** | **제품 결함** (T02 동결 시 Kotlin 컴파일 미확인) | 규칙대로 TESTING→CODING 복귀, `${newVersion}`, Kotlin 전체에서 같은 패턴 1건뿐 확인 → 재동결 `637b56a` 후 테스트 재개 |
| 2 | `G0TestSupport.kt` KDoc 안 `expected_v24/*.json`의 `/*`가 Kotlin 중첩 주석으로 해석 | 테스트 코드 | 문구 수정 |
| 3 | Robolectric SQLite 3.8.7의 `PRAGMA index_list`에 `origin`/`partial` 없음(null) → 구조 비교 불일치 | 테스트 환경 차이 | 값이 없을 때 `sqlite_master`로 같은 의미 계산(자동 인덱스명+PK 컬럼 → pk/u, 인덱스 SQL의 WHERE → partial). 비교 강도 유지 |
| 4 | "Robolectric엔 flutter_assets 없음" 가정이 틀림 — Gradle 단위 테스트가 자산을 합쳐 넣어 Native가 원본을 읽음 | 테스트 가정 | 자산 누락 테스트를 자산 경로 검증으로 교체. 자산 누락 상황은 NOT_RUN |
| 5 | Git Bash의 `./gradlew.bat`, PowerShell `cmd /c gradlew.bat` 모두 이 환경에서 실행 실패 | 실행 환경 | `sh ./gradlew`로 실행. worktree에 없는 추적 제외 래퍼(gradlew, gradlew.bat, gradle-wrapper.jar)를 메인 폴더에서 복사 — **T05에서 g1/g2/g3 worktree 만들 때도 같은 복사 필요** |

## 5. NOT_RUN

| 항목 | 이유 / 필요한 환경 |
|---|---|
| **S1 실기기 전체** — 업데이트 후 앱 미실행 울림, 첫 잠금 해제 전 부팅 후 울림, release APK의 자산 읽기(잠금 해제 전 포함), 10일 창 연장, 수면 위젯 | **D 필수 — T04 (사용자)** |
| CONCURRENT (Dart·Native 동시 open 반복) | 실제 앱 E/D 필요. 코드 근거: sqflite는 EXCLUSIVE 잠금 안에서 버전 재확인, Native onUpgrade도 잠금 안 재확인(재확인 분기만 단위 테스트) |
| Native SQL 원본 자산 누락 시 동작 | 제품에 주입 지점 없음 — 코드 리뷰만 |
| `onDiskVersion()` 확인 실패(null) 분기 | 주입 지점 없음 — 코드 리뷰만 |
| V4 `_initializeApp`/`_optionalStartupStep` (필수·선택 분리, 10초 상한, 재시도 시 Firebase 중복 방지) | private 함수 — 코드 리뷰만 |
| V4 release 빌드 실제 화면(원문 미노출), 네트워크 차단 | E + D release 필요 |
| targetSdk 36 동작 | Robolectric SDK 34 고정 |

## 6. 판정 — REPAIR-REJECT (부분 충족)

**관찰(양쪽 동일):** `user_version=24`인데 `friends`가 v16 형태(`owner_id` 없음)인 DB를 열면 예외 없이 열림. repair는 다른 누락 테이블·컬럼 14건을 채우지만 `friends`는 못 고침(허용 SQL로 `NOT NULL UNIQUE` 컬럼 추가 불가). 기준 구조와 다름. 옛 701 행은 보존.

**T01 기대 대비:**
- "과거 DROP/UPDATE·전체 onCreate 재실행으로 정상처럼 숨기지 않음" → **충족** (DROP 재실행 없음, 701 보존)
- "정의된 실패 전파와 재시도" → **미충족** — repair 뒤 필수 구조 검증으로 실패시키는 로직 없음

**G0 판단(구현 변경 안 함, 사용자 확인 요청):** 이 상태를 실패로 전파하면 repair로 고칠 방법이 없어 **앱 시작 실패 화면이 영구 반복되고 Native DB 접근(알람 재생 설정·스누즈·이력)도 전부 막힘**. 지금은 친구 공유 기능의 해당 쿼리만 실패함. 또한 이 상태가 생기려면 과거 Native가 v16 DB를 v17 이상으로 버전만 찍어야 하는데, 알려진 버전 불일치 사고(13/14, 15/16, 17/18) 중 이 조합을 만든 경로는 확인되지 않음(15/16은 다운그레이드 예외로 찍힘 없음). → 발생 가능성이 낮고, 실패 전파가 더 큰 피해라서 현 동작 유지를 제안.

**사용자 결정 (2026-09-14): A — 현 동작 유지 (ACCEPTED_RISK).** 근거로 사용자가 든 "재설치하면 해결"은 맞음(신규 설치는 `_onCreate`로 정상 구조). 단 두 가지를 보고함: ① 친구공유를 끊었다 다시 연결하는 것으로는 해결 안 됨(기기 안 테이블 구조 문제) ② 이 상태에서 만들어진 자동 백업을 재설치 후 복구하면, 현재 `restoreAll`이 행을 컬럼명 그대로 insert하므로 새 `friends`에 없는 `has_memos` 컬럼 때문에 **복구 전체가 실패할 수 있음** → G4(#19 복원 전 테이블·컬럼 검증) 주의사항으로 인계.
추가 근거: v4 기준 스토어 배포 DB 버전은 v12·v14·v15·v17·v18로 **v16은 배포된 적 없음** — 옛 형태 friends 테이블은 개발/테스트 기기에만 존재했음. v15 사용자가 버전만 찍힌 경우는 friends 테이블이 아예 없는 상태이며 repair가 정상 생성함(테스트로 확인된 MISSING 계열).

## 7. T03 판정

- 자동 테스트 범위: **PASS** — 모든 실행 케이스 통과. REPAIR-REJECT는 부분 충족을 사용자가 A(현 동작 유지)로 수용(2026-09-14).
- G0 전체 PASS 아님: S1 실기기(T04) 미실행. 실행계획 §2.2에 따라 T05 이후 그룹은 `PROVISIONAL / G0 실기기 미통과`를 상속.
