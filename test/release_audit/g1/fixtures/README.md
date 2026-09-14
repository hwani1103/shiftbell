# P1·alarm override 공통 fixture 기대값 초안

이 디렉터리는 T11a 선행 문서다. 기대값의 근거는 다음 두 곳으로 제한했다.

- `docs/release_audit/contracts.md` §2 시간/알람
- `출시전_코드감사_검토결과_v4_2026-09-13.md` #26, #31

제품 코드는 `shift_schedule`, `shift_alarm_templates`, `alarms`, `alarm_overrides`의 입력 컬럼과 현재 문자열 형태를 확인하는 데만 읽었다. Dart/Kotlin 계산 결과나 분기에서 expected를 복사하지 않았다. 이 문서는 빌드·테스트 실행 결과가 아니며 제품 코드를 수정하지 않았다.

## 파일

- `generation_cases.json`: 고정 now에서 규칙/불규칙 계산, 경계, 충돌, 빈 입력, override, 보호 대상, 멱등성 기대값.
- `state_change_cases.json`: D11 30일 정리와 D12 원본 변경·rename·A→B→A 되돌림의 DB 상태 변화 기대값.

## 독립 fixture 형식

`schedule.mode=regular`은 `start_date`의 패턴 위치가 `today_index`이며 날짜가 하루 늘 때 패턴 인덱스도 하나 증가한다. `irregular`은 `assigned_dates[yyyy-MM-dd]`만 원본으로 사용한다. 배정이 없거나 값이 `미설정`이면 기여가 없다.

템플릿은 배정일 기준이다.

- `day_offset=-1`: 배정일 전날 울림
- `day_offset=0`: 배정일 당일 울림
- `day_offset=1`: 배정일 다음날 울림

생성 비교의 정규 슬롯은 `(slot_time, shift_type, day_offset)`이고 `slot_time`은 `yyyy-MM-dd'T'HH:mm:ss`, 초 `00`, 밀리초 없음이다. 같은 **울림 시각**에 여러 배정이 기여하면 `day_offset=0`, `-1`, `1` 순서로 하나만 고른다. JSON의 `selected_priority`는 이를 `same_day`, `previous_day`, `next_day`로 표시한다.

`expected_generation_slots`는 override 적용 뒤의 desired 집합이다. 배열 순서는 판정에 사용하지 않고 `slot_time`, `shift_type`, `day_offset` 순으로 정렬해 비교한다. `expected_diff`가 있는 케이스는 기존 DB 행과의 차이까지 고정한다.

## 어댑터 규칙

1. Dart와 Kotlin은 같은 JSON과 같은 `now`/timezone을 입력으로 받는다. 테스트 중 시스템 현재 시각을 읽지 않는다.
2. 제품의 계산 결과를 위 정규 슬롯으로 투영한다. DB ID·생성시각은 desired 슬롯 비교에서 제외한다.
3. `template_query_result=error`는 조회 예외를 주입한다. 빈 배열과 같은 결과로 바꾸면 실패다.
4. `active_ring_id`는 행의 `type`과 별개로 보호한다. fixed 행도 현재 울리는 ID면 삭제·교체하지 않는다.
5. 멱등 케이스는 첫 실행 뒤 같은 입력을 다시 실행해 insert/delete/history가 모두 0이고 기존 ID가 같은지 검사한다.
6. 상태 변화 케이스는 `transaction_expectation=atomic`이면 원본 변경과 override 변화 사이 관찰 가능한 중간 상태가 없어야 한다.

## 필수 범위 대응

| 요구 경계 | 케이스 |
|---|---|
| 오늘~+9일, 지금 이전 제외 | `REGULAR_COLLISION_WINDOW_AND_PAST` |
| 전날/당일/다음날 기여와 충돌 우선순위 | `REGULAR_COLLISION_WINDOW_AND_PAST` |
| 불규칙 창 밖 배정의 창 안 기여 | `IRREGULAR_OUTSIDE_ASSIGNMENT_CONTRIBUTION` |
| 미설정 | `IRREGULAR_OUTSIDE_ASSIGNMENT_CONTRIBUTION` |
| 템플릿 0개와 조회 실패 구분 | `EMPTY_TEMPLATES_CLEAN_FIXED`, `TEMPLATE_QUERY_ERROR_NO_MUTATION` |
| skip/set_type | `OVERRIDE_SKIP_AND_SET_TYPE` |
| custom/snoozed/activeRing 보호 | `EMPTY_TEMPLATES_CLEAN_FIXED` |
| 멱등성 | `IDEMPOTENT_EXACT_EXISTING` |
| D11 30일 정리 | `D11_AGE_BOUNDARY` |
| D12 배정일/템플릿 변경 | `D12_ASSIGNMENT_CHANGE`, `D12_TEMPLATE_CHANGE` |
| 근무명 rename | `D12_SHIFT_RENAME` |
| A→B→A, 템플릿 변경 후 원복 | `D12_ASSIGNMENT_ABA`, `D12_TEMPLATE_ABA` |

## 후속 검증에서 추가로 볼 것

fixture는 계산과 DB 상태 기대값이다. P1 정책 버전은 첫 강제 갱신 **성공 뒤에만** 기록되는지, 알람 0개에서도 자정 Guard가 유지되는지, OS 예약 직전 재확인과 실패 재조정은 별도 G1 회귀 테스트에서 확인한다.
