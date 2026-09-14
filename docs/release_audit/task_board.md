# 작업판 (Task Board)

> **메인 폴더 사본만 유효.** 규칙은 `출시전_수정작업_그룹별_실행계획_및_세션인계_2026-09-14.md` §11.
> 작업을 시작·중단·완료할 때마다 **아래 두 줄**과 표를 갱신한다. 두 AI는 동시에 작업하지 않는다.

**Claude 이어서 할 작업:** T06 — G1 수정 (`shiftbell-g1`, 기준 `c0b2e73`). 여러 번 끊겨도 Claude가 이어감
**Codex 지금 할 수 있는 작업:** T07 — G2 수정 (`shiftbell-g2`, 기준 `c0b2e73`). 끝나면 T08(G3, `shiftbell-g3`) → T09. 먼저 contracts.md §0·§4·§7·§8 필독

---

## 기준 정보

| 항목 | 값 |
|---|---|
| T00 커밋 (`dev`) | `dafe06b303d6959cffee83495ec38b3c5861524c` |
| G0 기준 커밋 (T05) | `c0b2e73` — worktree shiftbell-g1/g2/g3 (브랜치 release/g1~g3). PROVISIONAL(S1 미통과) |
| G4 기준 커밋 (T17) | - |
| 호스트 RAM | 5.9GB (2026-09-14 확인). 교대 전 `gradlew --stop`, 에뮬레이터 종료 |
| 결정 | D1~D12 전부 확정 (2026-09-14). D7·D8 후속 판단은 T16에서 사용자 보고 |

## 작업 상태

상태 값: `대기` `진행중` `중단(토큰)` `동결` `완료` `PASS` `FAIL` `BLOCKED`

| T | 작업 | 주 담당 | 대체 | 선행 | 상태 | 마지막 SHA | 메모 |
|---|---|---|---|---|---|---|---|
| T00 | 준비 (문서 커밋, 뼈대, Gradle 메모리) | Claude | — | 없음 | 완료 | `dafe06b` | Gradle jvmargs 8G→3G, 빌드로는 아직 미확인(첫 빌드인 T03에서 확인) |
| T01 | G0 fixture 초안 (docs만) | Codex | Claude | 없음 | 완료 | `dafe06b` (기준) | Codex: v1~v23 SQL 23개·출처/입력 manifest·독립 기대값. 실행 없음, 문서 커밋은 Claude |
| T02 | G0 수정 (`shiftbell-g0`) | Claude | — | T00 | 동결 | `637b56a` | T03 중 컴파일 결함 수정 후 재동결 |
| T03 | G0 테스트 | Claude | Codex | T01, T02 동결 | PASS | `c06ffea` | Flutter 139/139, Kotlin 23/23. REPAIR-REJECT는 사용자 결정 A(유지). S1은 T04 |
| T04 | 실기기 S1 | 사용자 | — | T03 | 대기 | - | 절차: g0/t04_s1_device_procedure.md |
| T05 | contracts 확정, G0 기준 커밋, g1/g2/g3 worktree | Claude | — | T03 PASS | 완료 | `c0b2e73` | 공통 선언 data_revision_provider.dart 포함 |
| T06 | G1 수정 | Claude | 없음 | T05 | 대기 | - | |
| T07 | G2 수정 | Codex | Claude | T05 | 대기 | - | |
| T08 | G3 수정 | Codex | Claude | T05 | 대기 | - | |
| T09 | G4/G5 준비 문서 (읽기 전용) | Codex | Claude | T05 | 대기 | - | |
| T10 | 연결 반영 + 연결 동결 커밋 | Claude | — | T06·T07·T08 동결 | 대기 | - | |
| T11 | G1 교차 리뷰 + 공통 fixture 기대값 | Codex | — | T10 | 대기 | - | |
| T12 | G1 테스트 | Claude | Codex | T10, T11 | 대기 | - | |
| T13 | G2 테스트 | Claude | Codex | T10 | 대기 | - | |
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
