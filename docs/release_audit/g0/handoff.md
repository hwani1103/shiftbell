# G0 handoff

```text
그룹 / 담당 / worktree / branch: G0 / Claude / C:\Users\Administrator\Desktop\shiftbell-g0 / release/g0
공통 기준 SHA / 최종 소스 SHA: dafe06b / 0f9e6a1 (R0 반영 재동결) · dev 병합 94ff08f
상태: CODE_FROZEN(0f9e6a1) + 자동 테스트 PASS(Flutter 146, Kotlin 23) + T04-E 에뮬레이터 S1 PASS — 실기기 D는 G6 필수(PROVISIONAL 유지)
수정한 감사 번호: #1(C01 + H16 native), #8(H16 Dart), #31 스키마(v24 alarm_overrides), V4
실제 변경 파일(소유권 범위 검사 결과): 범위 밖 파일 수정 없음
  - assets/db/migrations.json (신규) — SQL 단일 원본: migrations v2~v24 + repair
  - lib/services/db_migration_runner.dart (신규) / android/.../DbMigrationRunner.kt (신규) — 실행기 쌍
  - android/.../DatabaseHelper.kt — v24, onUpgrade 네이티브 마이그레이션, onCreate/onDowngrade 예외, onOpen repair, 게이트 교체
  - lib/services/database_service.dart — 마이그레이션/onCreate/onOpen/onDowngrade 영역만 (옛 _onUpgrade 삭제)
  - lib/main.dart — main()/_initializeApp/_optionalStartupStep/ErrorWidget만 (병렬 구간부터 G1 소유)
  - lib/screens/startup_gate.dart (신규, V4)
  - CLAUDE.md(DB 규칙 부분), DB_스키마_변경_가이드.md
  - 통합 담당자 파일(담당=Claude 본인이 같은 브랜치에서 반영): pubspec.yaml(자산 등록), android/app/build.gradle.kts(checkPair 1개), lib/l10n/app_ko.arb·app_en.arb(startup* 4키)
공통 파일/API/ARB 연결 요청 및 반영 SHA: 위 통합 담당자 파일 반영 cf7421b. 다른 그룹 요청 없음.
사용자 결정 확인(D 번호·선택·일시): D1~D12 전부 확정(2026-09-14). G0 해당: D4 폐기(헤드리스 없음), D10 v24 도입.
최종 동작과 회귀 금지 규칙 준수:
  - 과거 마이그레이션 원문 유지(v17 DROP friends, v8~v11 UPDATE 포함). repair는 화이트리스트 3종만, 과거 SQL 재실행 없음
  - Native onCreate로 빈 DB 생성 안 함(예외), onDowngrade 예외, 버전 확인 실패 시 최신 가정(fail-open) 제거
  - ALTER 실패를 삼키지 않음(컬럼 실재 확인 시에만 건너뜀), 실패는 트랜잭션 롤백 후 다음 접근 재시도
  - 영구 이력 테이블(alarm_history/alarm_creation_log) 무변경, 헤드리스 Flutter 없음
추가/변경 테스트와 실제 실행 명령: test/release_audit/g0/*, G0NativeMigrationTest.kt, G0TestSupport.kt, AlarmRefreshEngineH2Test.kt(fixture 교체), tool/g0/build_fixtures.py — 명령은 test_results.md 1장
  실행한 것: flutter pub get / flutter analyze lib/services/db_migration_runner.dart lib/services/database_service.dart lib/main.dart lib/screens/startup_gate.dart
  → error 0, warning 1(database_service.dart unused import dart:convert — 변경 전 코드에서도 미사용, 범위 밖), 나머지 info(print 등 기존 린트)
테스트 결과(실행 빌드·환경·expected/actual·증적): g0/test_results.md — Flutter 139/139, Kotlin 23/23 PASS. REPAIR-REJECT 부분 충족 → 사용자 결정 A(유지, ACCEPTED_RISK)
미실행 실기기/Console 항목: S1 전체(D 필수) — 업데이트 후 앱 미실행 울림, 첫 잠금 해제 전 부팅, 동시 open, release APK에서 flutter_assets 자산 읽기(잠금 해제 전 포함), 10일 창/수면 위젯
잔여 위험·다음 그룹 주의사항:
  1. [T03 첫 단계] Kotlin 컴파일 미확인 — gradlew :app:checkDartKotlinSync → :app:compileDevDebugKotlin 먼저.
  2. [T03] AlarmRefreshEngineH2Test fixture 깨짐 예상 — Native onCreate가 이제 예외라 dbHelper.writableDatabase로 빈 DB를 만드는 준비 방식이 실패함. user_version=24 파일을 먼저 만들고 헬퍼로 여는 방식으로 교체 필요(이 테스트 주석의 Robolectric 'Illegal connection pointer' 이력 주의). Robolectric엔 flutter_assets가 없으므로 DbMigrationScript.overrideForTest에 저장소 assets/db/migrations.json을 parse해서 주입(주입 안 하면 onOpen repair는 건너뛰고 onUpgrade는 실패).
  3. Native 자산 경로 flutter_assets/assets/db/migrations.json은 release·잠금 해제 전 실제 읽기를 S1 실기기로만 확인 가능. 실패하면 v4 #1-2 차선책(양쪽 코드에 SQL + 빌드 시 문자열 비교)으로 전환.
  4. Dart onDowngrade 예외는 v4에 명시 없던 G0 판단 — 예전엔 sqflite가 버전을 조용히 낮게 찍었음. 개발 중 구버전 APK 덮어 설치 시 앱이 시작 실패 화면으로 멈춤.
  5. alarm_overrides의 CHECK/UNIQUE 제약은 G0 판단으로 추가 — G1이 같은 슬롯을 다시 쓸 때 upsert 처리 필요, G4 복원 검증 규칙과 일치해야 함.
  6. repair는 v16 형태 friends(owner_id 없음)를 못 고침(ALTER로 NOT NULL UNIQUE 추가 불가) — v17 마이그레이션이 정상 실행된 DB만 전제.
  7. 관찰(감사 목록 밖, 수정 안 함): _initDatabase가 Device Protected 경로 조회 실패 시 일반 경로로 fallback → Native와 다른 DB 파일을 쓰게 될 수 있음.
  8. 시간값: 선택 초기화 10초 상한, "준비 중" 표시 15초는 측정값이 아닌 정책값.
  9. v1 스키마 원본은 저장소 현재 코드에 없음 — v1 fixture는 git 이력 확인 필요(T01).
```

## 진행 기록 (끊김 대비 — 하위 작업마다 한 줄)

| 일시 | 담당 AI | T | 감사 번호 / 하위 작업 | 커밋 SHA | 다음에 할 일 |
|---|---|---|---|---|---|
| 2026-09-14 | Claude | T02 | #1/#8/#31 스키마: migrations.json + Dart/Kotlin 실행기 + DatabaseHelper 게이트 교체 + database_service 연결 + checkPair + pubspec 자산. 컴파일/테스트 미실행 | `bcda3eb` | V4 시작 실패 화면(main.dart, ARB) → CLAUDE.md/DB 가이드 갱신 → contracts 초안 → flutter analyze → 동결 |
| 2026-09-14 | Claude | T02 | V4 시작 실패 화면(startup_gate, main.dart, ARB) + CLAUDE.md/DB 가이드 + contracts 초안 + flutter analyze(error 0) → **CODE_FROZEN** | `cf7421b` | T03: Kotlin 컴파일 확인 → H2 테스트 fixture 교체 → T01 fixture로 S1 R/F 테스트 |
| 2026-09-14 | Codex | T01 | 역사 onCreate/onUpgrade 조사, v1~v23 SQL 23개·입력/출처 manifest·독립 기대값·T03 절차 작성 완료. SQL/앱/빌드/테스트 미실행 | 문서 미커밋, 기준 `dafe06b` | T03: `fixtures_draft/README.md`부터 확인. 제품 대상 `cf7421b` 재확인 후 테스트 |

## T01 인계 — Codex (2026-09-14)

- 작업 위치/브랜치/HEAD: `C:\Users\Administrator\Desktop\shiftbell` / `dev` / `dafe06b303d6959cffee83495ec38b3c5861524c`.
- 시작 시 이미 `contracts.md`, 이 handoff, 작업판에 Claude의 T02 미커밋 변경이 있었으며 보존했다. Codex 변경은 `g0/fixtures_draft/` 신규 문서와 이 인계 추가·작업판 갱신뿐이다. G0 제품 소스 상태는 위의 CODE_FROZEN 그대로다.
- 산출물: [fixture 사용 안내](fixtures_draft/README.md), [독립 기대값](fixtures_draft/expected.md), `manifest.json`, `v01.sql`~`v23.sql`. 필수 v12·14·15·17·18·23은 역사 onCreate 출처. v1·3·4·5·13·21은 재구성으로 표시했고 실제 배포본이라고 주장하지 않는다.
- 확인: Git 역사 읽기, 텍스트 추출/문서 생성, 파일 해시·버전 표기·INSERT 수·필수 필드 대조, `git diff --check`. **SQL 실행·실제 SQLite 생성·제품 코드 실행·빌드·테스트 없음**. G0 마이그레이션 PASS나 S1 검증 완료를 뜻하지 않는다.
- §11.2-7에 따라 메인 공유 문서 커밋은 통합 담당자에게 남긴다. 새 소스 SHA 없음. 공통 계약 변경 요청 없음. 빌드/에뮬레이터를 시작하지 않아 이번 작업이 남긴 데몬 없음.
- 다음 작업: T03(Claude 주 담당, Codex 대체 가능). 테스트의 첫 단계는 기존 인계의 Kotlin 컴파일 확인이며 fixture 실행 오류는 T03에서 기록한다. 필수 실기기 T04는 NOT_RUN 유지.
| 2026-09-14 | Claude | T03 | 테스트 기반 커밋(빌더·fixture·Dart/Kotlin 테스트·H2 fixture 교체). Dart G0 36개 PASS(음성 대조 추가 전), Kotlin 실행 중 | `61a162c` | Kotlin testDevDebugUnitTest 결과 확인 → Dart 전체 재실행 → test_results.md 작성 → 판정 |
| 2026-09-14 | Claude | T03→T02 | **Kotlin 컴파일 실패(제품 코드)**: DatabaseHelper.kt:143 문자열 템플릿 `$newVersion으로` - Kotlin이 한글을 식별자로 읽음. T02 동결 때 Kotlin 컴파일 미확인이 원인. 규칙대로 TESTING→CODING 복귀 | `61a162c` | 한글 인접 템플릿 전수 수정(`${}`) → 재동결 커밋 → Gradle 단위 테스트 → Dart 재실행 |
| 2026-09-14 | Claude | T03 | 제품 재동결 `637b56a`(한글 인접 템플릿 수정) 후 테스트 재개. Kotlin 환경 차이 반영 `c06ffea`. **Flutter 139/139, Kotlin 23/23 PASS**. REPAIR-REJECT 부분 충족 → 사용자 확인 | `c06ffea` | T04 사용자 S1 실기기 / T05: contracts 확정, G0를 dev에 병합, g1~g3 worktree(추적 제외 gradle 래퍼 복사 포함) |

## T03 이후 추가 주의사항 (T05·G1 인계)

- g0 worktree 생성 시 추적 제외 파일(android/gradlew, gradlew.bat, gradle/wrapper/gradle-wrapper.jar)이 없어 Gradle이 안 돌았음 → 새 worktree마다 메인 폴더에서 복사.
- 이 환경에선 `sh ./gradlew`로 실행(`gradlew.bat`은 Git Bash·cmd 모두 실패).
- Gradle 단위 테스트에는 flutter 자산이 합쳐져 Native `DbMigrationScript.load`가 실제 원본을 읽음 → Native DB 테스트를 새로 짤 때 onOpen repair가 실제로 돈다는 전제로 작성.
- Robolectric SQLite는 3.8.7 — 최신 SQLite 문법(DROP COLUMN 등)·PRAGMA 열 차이 주의.
- REPAIR-REJECT: 사용자 결정 A(현 동작 유지, 2026-09-14). **G4 주의:** 이 상태에서 만든 백업은 옛 friends 컬럼(has_memos 등)을 담아 현재 restoreAll에서 복구 전체가 실패할 수 있음 → #19 복원 전 컬럼 검증에서 처리할 것(test_results.md 6장).
| 2026-09-14 | Claude | T03 | REPAIR-REJECT 사용자 결정 A(유지) 기록, 백업 복구 연쇄 위험을 G4 인계 | - | T05 |
| 2026-09-14 | Claude | T02(R0) | R0 교차 리뷰(High 2·Medium 2) 반영 코드+테스트 작성, 커밋. **flutter analyze·test 미실행**(에뮬레이터 케이스 ② 진행 중) | `6214514` | 케이스 ② 종료 후 analyze → flutter test 전체 → Codex R0-T 재현 테스트 실행 → 재동결 → dev 반영 |
| 2026-09-14 | Claude | T02·T03(R0) | R0 4건 반영·재현 테스트 반입·flutter test 146/146 → 재동결, dev 병합(G1 새 기준) | `0f9e6a1` / `94ff08f` | T06 G1 시작 |
