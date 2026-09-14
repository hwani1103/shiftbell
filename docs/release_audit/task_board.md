# 작업판 (Task Board)

> **메인 폴더 사본만 유효.** 규칙은 `출시전_수정작업_그룹별_실행계획_및_세션인계_2026-09-14.md` §11.
> 작업을 시작·중단·완료할 때마다 **아래 두 줄**과 표를 갱신한다. 두 AI는 동시에 작업하지 않는다.

**Claude 이어서 할 작업:** T11 리뷰(`g1/review.md`, High 5·Medium 3) 분류 → G1 수정·재동결 → T12. T14(G3 테스트, `98c4831`)도 가능. T13 완료(`0cbe392`)
**Codex 지금 할 수 있는 작업:** 없음 — T11 교차 리뷰 완료(`CHANGES_REQUESTED`, High 5·Medium 3). G1 수정·재동결 전 T12 진행 보류

---

## 기준 정보

| 항목 | 값 |
|---|---|
| T00 커밋 (`dev`) | `dafe06b303d6959cffee83495ec38b3c5861524c` |
| G0 기준 커밋 (T05) | `c0b2e73`(g2·g3 시작점) → **G1 `94ff08f`**(R0 반영 재병합). worktree shiftbell-g1/g2/g3. PROVISIONAL(실기기 D 미통과, E PASS) |
| G4 기준 커밋 (T17) | - |
| 호스트 RAM | 5.9GB (2026-09-14 확인). 교대 전 `gradlew --stop`, 에뮬레이터 종료 |
| 결정 | D1~D12 전부 확정 (2026-09-14). D7·D8 후속 판단은 T16에서 사용자 보고 |

## 작업 상태

상태 값: `대기` `진행중` `중단(토큰)` `동결` `완료` `PASS` `FAIL` `BLOCKED`

| T | 작업 | 주 담당 | 대체 | 선행 | 상태 | 마지막 SHA | 메모 |
|---|---|---|---|---|---|---|---|
| T00 | 준비 (문서 커밋, 뼈대, Gradle 메모리) | Claude | — | 없음 | 완료 | `dafe06b` | Gradle jvmargs 8G→3G, 빌드로는 아직 미확인(첫 빌드인 T03에서 확인) |
| T01 | G0 fixture 초안 (docs만) | Codex | Claude | 없음 | 완료 | `dafe06b` (기준) | Codex: v1~v23 SQL 23개·출처/입력 manifest·독립 기대값. 실행 없음, 문서 커밋은 Claude |
| T02 | G0 수정 (`shiftbell-g0`) | Claude | — | T00 | 동결 | `0f9e6a1` | R0 교차 리뷰 4건 반영 후 재동결 |
| T03 | G0 테스트 | Claude | Codex | T01, T02 동결 | PASS | `0f9e6a1` | Flutter 146/146(R0 재검증 포함), Kotlin 23/23. REPAIR-REJECT 사용자 결정 A |
| T04 | S1 확인: **E** 에뮬레이터(Claude) / **D** 삼성 실기기(사용자, G6로 미룸) | Claude / 사용자 | — | T03 | **E PASS** · D 대기 | - | E: 케이스 ①(업데이트 후 앱 미실행)·②(재부팅 후 잠금 해제 전) PASS, ③④⑤ 생략. 중복 수신 관찰 G1 인계. 결과 g0/test_results.md 8장. D는 G6 필수 |
| T05 | contracts 확정, G0 기준 커밋, g1/g2/g3 worktree | Claude | — | T03 PASS | 완료 | `c0b2e73` | 공통 선언 data_revision_provider.dart 포함 |
| T06 | G1 수정 | Claude | 없음 | T05 | 동결 | `9b8a586` | 기준 `94ff08f`. 커밋 9개, Kotlin 65/65·Flutter 205/205(코딩 중 재현·회귀 테스트, 공식 판정 T11/T12). 연결 요청 6건. 실기기 S1~S16 미실행 |
| T07 | G2 수정 | Codex | Claude | T05 | 동결 | `5cda0e0` | #21·#24·#30, #29 정적 조사만(S12 NOT_RUN). 연결 요청 0 |
| T08 | G3 수정 | Codex | Claude | T05 | 동결 | `98c4831` | #15·#22·#17(수면). 연결 요청 2건(T10) |
| T09 | G4/G5 준비 문서 (읽기 전용) | Codex | Claude | T05 | 완료(초안) | - | g4/prep_writer_inventory.md(G1 수정 전 초안), g4/prep_s17_failure_injection.md, g5/prep_data_collection.md |
| T10 | 연결 반영 + 연결 동결 커밋 | Claude | — | T06·T07·T08 동결 | 완료 | G1 `2b82adc` · G2 `4a8f67e` · G3 `98c4831` | 그룹별 연결 커밋(병합은 5단계). G1 Manifest V6, G2 G2-01·02(main.dart 재시도·공유 화면 대기 안내+ARB 4), G3 연결 코드 없음. 3개 모두 `flutter build apk --flavor dev --debug` exit 0. contracts §7.2 키·소유권 `ac672fe`. 남은 요청: G2-03·G3#2→G4, G2-04→G5 |
| T11a | (선행) G1 알람 계산 기대값 — contracts §2·v4 #26/#31만 근거, G1 코드 미참조. docs/release_audit/g1/fixtures_draft_p1/ | Codex | — | T05 | 완료 | - | 생성 6건·상태 변화 6건 JSON + README. T06/T12 테스트에서 사용 |
| R0 | (추가) G0 교차 리뷰 — release/g0 diff 읽기 전용, g0/review_codex.md | Codex | — | T05 | 완료 | - | CHANGES_REQUESTED: High 2·Medium 2 → Claude 판정 전부 타당, T02 재수정 |
| R0-T | (추가) R0 재현 테스트 초안 — docs/release_audit/g0/r0_repro_tests/ (수정 전 FAIL·수정 후 PASS), 실행은 Claude | Codex | — | R0 | 완료(초안) | - | 테스트 4개 + README(R0-02 timeout 주입 지점 요구). Claude가 에뮬레이터 종료 후 G0 수정본에 대입·실행 |
| T11 | G1 교차 리뷰 + 공통 fixture 기대값 | Codex | — | T10 | 완료(`CHANGES_REQUESTED`) | 대상 `2b82adc` | High 5·Medium 3. `g1/review.md`, `g1/review_fixture_additions.json`; 빌드·테스트 미실행 |
| T12 | G1 테스트 | Claude | Codex | T10, T11 | 대기 | - | |
| T13 | G2 테스트 | Claude | Codex | T10 | 완료 | release/g2 `0cbe392` (대상 `4a8f67e`) | F 40/40·전체 179/179·FS 16/16. #21 부분 PASS·#24 로컬 PASS(서버 경로 S9)·#29 NOT_RUN·#30 앱 측 PASS. FS 관찰 4건(서버 형식·크기·회차 강제 없음) → T16. `g2/test_results.md` |
| T14 | G3 테스트 | Claude | Codex | T10 | 대기 | - | |
| T15 | 실기기 S2·S3·S4·S14, 두 기기 S9 | 사용자 | — | T12~T14 | 대기 | - | |
| T16 | S9·S12 보고 → D7·D8 후속 선택 | Codex | Claude | T13, T15 | 대기 | - | |
| T17 | G1→G2→G3 통합, G4 기준 커밋 | Claude | — | T12~T16 | 대기 | - | |
| T18 | G4 수정 | Claude | 없음 | T17 | 대기 | - | |
| T19 | G4 테스트 (S17 실패 주입, S5·S6) | Codex | Claude | T18 동결 | 대기 | - | |
| T20 | 실기기 S5·S17, 재설치 V2 | 사용자 | — | T19 | 대기 | - | |
| T21 | G5 설정 수정 | Claude | — | T20 | 대기 | - | |
| T22 | G5 개인정보·데이터 보안 초안 (docs만) | Codex | Claude | T20 | 대기 | - | |
| T23 | G5 테스트 (S10, prod release) | Codex | Claude | T21, T22 동결 | 대기 | - | |
| T24 | Console 실제 값 확인 (S12, V5, V7) | 사용자 | — | T21 | 대기 | - | |
| T25 | G6 통합 시나리오 실행 | Claude | Codex | T23, T24 | 대기 | - | |
| T26 | G6 최종 판정 | Codex | Claude(분리 불가 표시) | T25 | 대기 | - | |

## 교대 기록 (최근이 아래)

| 일시 | AI | T | 한 일 / 멈춘 지점 | SHA |
|---|---|---|---|---|
| 2026-09-14 | Claude | T00 | 완료. 문서 3개·release_audit 뼈대·Gradle jvmargs(8G→3G) 커밋. push 안 함 | `dafe06b` |
| 2026-09-14 | Claude | T02 | G0 수정 완료·동결 (DB v24 네이티브 마이그레이션, V4). Kotlin 컴파일·테스트는 T03 | `cf7421b` |
| 2026-09-14 | Codex | T01 | fixture 초안 완료: 필수 6개 버전 포함 v1~v23 SQL, 재구성본 구분, 입력 manifest·독립 기대값·T03 절차. 문서 수준 대조만 수행, SQL/테스트 NOT_RUN | 기준 `dafe06b`, 문서 미커밋 |
| 2026-09-14 | Claude | T03 | 자동 테스트 PASS(조건부). 중간에 제품 컴파일 결함 1건 발견→T02 재수정·재동결(637b56a). REPAIR-REJECT 사용자 확인 대기 | `c06ffea` |
| 2026-09-14 | Claude | T05 | contracts 확정, G0를 dev에 병합(기준 커밋), g1/g2/g3 worktree 생성·gradle 래퍼 복사 | `c0b2e73` |
| 2026-09-14 | Codex | T07·T08·T09 | G2 동결 5cda0e0, G3 동결 98c4831, G4/G5 준비 문서 초안 (Claude가 작업판 반영) | `5cda0e0` / `98c4831` |
| 2026-09-14 | Codex | T11a·R0 | T11a 기대값 12건, R0 리뷰 CHANGES_REQUESTED(High 2·Medium 2) → Claude가 T02 재수정 착수 | - |
| 2026-09-14 | Codex | R0-T | R0-01~04 재현 테스트 초안 4개 + README (코드 읽기만) | - |
| 2026-09-14 | Claude | T04-E | 에뮬레이터 S1 케이스 ①② PASS(1차 ② 무효는 시드 레이블 문제), 중복 수신 관찰 G1 인계, 에뮬레이터 종료 | - |
| 2026-09-14 | Claude | T02·T03(R0) | R0 4건 반영 재동결 0f9e6a1, flutter test 146/146, dev 병합 94ff08f, release/g1 새 기준으로 이동 | `94ff08f` |
