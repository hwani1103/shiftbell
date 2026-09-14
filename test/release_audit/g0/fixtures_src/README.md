# T01 — G0 과거 DB fixture 초안

작성: Codex / 2026-09-14. 상태: **DRAFT / NOT_RUN**. 메인 `dev` 기준 `dafe06b303d6959cffee83495ec38b3c5861524c`, 향후 T03 제품 대상 `cf7421b`(G0 동결). SQL 생성 문서와 입력 manifest만 작성했다. DB 생성, 마이그레이션, 앱, 빌드, 테스트는 실행하지 않았다.

## 출처와 범위

`v01.sql`~`v23.sql`은 각각 **빈 임시 DB 하나에 단독 적용**하는 SQL이다. 서로 이어 붙이지 않는다. 각 파일은 역사 스키마 DDL, 합성 사용자 데이터 INSERT, 해당 `PRAGMA user_version`, 트랜잭션으로 구성된다. 실제 사용자 데이터나 배포 DB 덤프가 아니다. 프리셋도 공장 초기값이 아니라 사용자가 변경한 설정을 가정했다.

`manifest.json`은 파일별 전체 Git SHA, 소스 경로/일부 행 번호, 생성 경위, SHA256, **마이그레이션 전 입력 행**을 담는다. 입력 행을 v24 전체 expected로 사용하면 안 된다. 기대 동작은 [expected.md](expected.md)에 별도로 적었다. G0 `assets/db/migrations.json`은 읽거나 복사하지 않았다.

모든 출처 파일은 `lib/services/database_service.dart`. Git의 역사 `_onCreate`에서 `db.execute`의 DDL을 추출했고 `_onUpgrade`로 변경 경계를 대조했다. Dart 프리셋 삽입 루프 대신 고정된 합성 INSERT를 넣었다. 직접 생성 스키마의 컬럼 순서는 유지했으며, 업그레이드 결과와 비교할 때 컬럼 순서 자체를 동등성 조건으로 삼지 않는다.

| 버전 | 역사 커밋 / 구성 | 구분 |
|---|---|---|
| 1 | `059bd255ac92`의 v2 onCreate에서 v2 추가분(shift_colors, shift_alarm_templates)을 제외 | 재구성: v1 원본 커밋 없음 |
| 2 | `059bd255ac92` | 역사 onCreate |
| 3·4·5 | 직전 fixture DDL + `5fdbc880bb80` 역사 onUpgrade의 해당 분기 | 재구성 |
| 6 | `7ce304f324a2` | 역사 onCreate |
| 7 | `eeef178efc97` | 역사 onCreate |
| 8 | `470a9686d5b2` | 역사 onCreate |
| 9 | `6166e076f43b` | 역사 onCreate |
| 10 | `efb0cce1c20b` | 역사 onCreate |
| 11 | `e1147fe48e97` | 역사 onCreate |
| **12** | `120b8103eed4` | 역사 onCreate, date_memos 포함 |
| 13 | v12 DDL + `5fdbc880bb80` 역사 v13 분기 | 재구성, 생성 이력 추가 |
| **14** | `c9a8c5c37a79` | 역사 onCreate, OT 포함 |
| **15** | `555cb20d48fd` | 역사 onCreate, shift_durations 포함 |
| 16 | `b674c731f629` | 역사 onCreate, owner_id 이전 friends |
| **17** | `65867d6cfe4b` | 역사 onCreate, owner_id friends |
| **18** | `ca82d69d0cf1` | 운영 스냅샷 onCreate, custom_shift_colors |
| 19 | `08b48f37d627` | 역사 onCreate, day_offset |
| 20 | `64c6224bb5a8` | 역사 onCreate, date_schedules |
| 21 | v20 DDL + `5fdbc880bb80` 역사 v21 분기 | 재구성, condition_shift_times |
| 22 | `a97e1d9a7ecd` | 역사 onCreate, 수면 테이블 |
| **23** | `5fdbc880bb80` | 역사 onCreate, 일정 알림 컬럼 |

재구성본은 실제 출시 스냅샷으로 주장하지 않는다. 조회한 도달 가능한 Git 이력에서 DB 버전은 2→6, 12→14, 20→22로 건너뛴다. v1·3·4·5·13·21 지원 검증은 역사 분기로 추론한 경계 검증이다. 과거 ALTER 실패나 native 버전 선행 기록으로 손상된 DB는 정상 fixture와 별개로 T03에서 변형해야 한다.

## 데이터 의도

- 프리셋 1·2·3과 custom 타입 41: volume 0.43, duration 7, vibration_strength 1 같은 수정값으로 과거 UPDATE의 잘못된 재실행 탐지. 해당 컬럼이 없는 구버전에는 삽입하지 않는다.
- 근무표 1: Day/Night/Off 규칙 패턴, 날짜별 Night 예외, 색상·근로시간 JSON. 직렬화는 모델의 쉼표 문자열과 JSON 저장 형식에 맞췄다.
- 알람 101/102/103: fixed/custom/snoozed와 NULL shift_type. 고정 시계는 `2026-09-14T05:00:00+09:00`, 예정일은 다음 날이다. fixture 생성 당시 벽시계를 사용하지 않는다.
- 이력 301·생성 원장 501: 이미 alarms에 없는 999의 과거 기록. 마이그레이션이 행을 정리하면 실패다.
- 메모 401/402: 같은 날짜의 순서, 작은따옴표 포함 본문. OT 601: 90분.
- friends 701/702: 캐시 있음/아직 조회하지 않음(NULL). v16에는 NULL을 허용하지 않으므로 701만 넣는다. 캐시 JSON은 DB 보존 검증용 최소 합성 객체이며 Firestore/친구 모델 통합 fixture는 아니다.
- 일정 801, 야간 출퇴근 시간, 완료 수면 901/진행 중 후보 902, 옛 취침 기준: 새 기능의 기존 데이터/NULL 보존 검증. 현재 미사용 sleep_expected_bedtime에도 잔존 데이터를 넣었다.

## T03 사용 순서 (아직 미실행)

1. 메인 작업판·handoff와 `shiftbell-g0`의 HEAD/status/diff를 재확인한다. 동결 SHA가 바뀌면 테스트 대상 SHA를 새로 기록한다.
2. 각 SQL로 실제 SQLite 임시 파일을 만들고, 먼저 user_version·테이블·입력 행·무결성을 확인한다. SQL을 세미콜론 단순 분리하기보다 SQLite script 실행 또는 문자열을 이해하는 실행기를 쓴다. 기존 앱 DB에는 적용하지 않는다.
3. Native/Dart 업그레이드는 **서로 독립된 같은 입력 DB 복사본**에서 실행한다. onOpen repair 후에도 비교하고 다시 열어 멱등성을 확인한다. mock 성공 반환만으로 통과시키지 않는다.
4. Dart 신규 onCreate를 실제 실행한 v24 DB를 별도로 생성하여 구조를 비교한다. 프리셋 사용자 값과 신규 초기값, 과거 데이터 행은 구조 비교와 분리한다. Robolectric이 만든 DB를 Dart 실행 결과로 표시하지 않는다.
5. 실패 주입·손상/repair·V4 widget·동시 open·에뮬레이터는 [expected.md](expected.md)의 대조표를 적용한다. 빌드/테스트는 한 번에 하나, 제품 코드 결함이면 T03을 멈추고 Claude 수정→재동결 절차로 돌아간다.
6. 결과는 메인의 `g0/test_results.md`에 환경·대상 SHA·expected/actual·증적과 함께 기록한다. S1 실기기/잠금 해제 전 자산 접근은 T04까지 NOT_RUN이다.

T01은 문서 작업이므로 §11.2-7에 따라 이 문서들을 메인에 남긴다. `dev` 문서 커밋은 통합 담당자 Claude가 수행한다. 제품 worktree 변경이나 테스트 코드 작성은 T01 범위에 포함하지 않는다.
