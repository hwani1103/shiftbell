# T11 — G1 교차 리뷰 (Codex)

작성일: 2026-09-14
리뷰 대상: `release/g1` `2b82adc` (`git diff 94ff08f..2b82adc`; 동결 `9b8a586` + T10 Manifest 연결)
수정 대상/동결: `2b82adc..e6e679a` (`438a9b9`, `e6e679a`; 사용자 승인 예외로 Codex 수정)
근거: 실행계획 §5 G1 회귀 금지 규칙, `contracts.md` §2·§3, v4 #3·#5·#13·#14·#16·#26·#27·#31

최초 교차 리뷰는 제품 코드 수정 없이 수행했다. 이후 사용자 승인 예외에 따라 Codex가 T11-01~T11-08의 재현 테스트를 먼저 추가해 수정 전 FAIL을 확인하고, G1 소유 파일만 수정한 뒤 같은 테스트의 PASS와 전체 회귀를 확인했다.

## 발견 사항

### T11-01 — High — 정확한 알람 권한 확인 실패가 여전히 “허용”으로 변환된다

- **상태:** **FIXED — `e6e679a`**
- **수정:** bool 호환 API는 `granted`일 때만 true를 반환한다. 예외·null·비 bool 결과의 `unknown`은 성공으로 축약하지 않는다.
- **테스트:** 수정 전 `g1_schedule_failure_test.dart` 2건 FAIL(`Expected false, Actual true`) → 수정 후 PASS.
- **위치:** `lib/services/permission_service.dart:55-66,84-87,99-104`; 호출 결과를 신뢰하는 `lib/screens/permission_intro_screen.dart:42-50,255-267`
- **조건:** `checkExactAlarmPermission` MethodChannel 호출이 예외를 던지거나 bool 이외 값을 반환한다.
- **재현:** 채널 mock이 `PlatformException`을 던지게 한 뒤 `checkPermissions()` 또는 `requestAllPermissions()`를 호출한다. `checkExactAlarmPermissionState()`는 `unknown`을 만들지만 bool 호환 함수가 `unknown != denied`를 계산해 `true`를 반환한다. 권한 소개 화면은 세 bool이 모두 true이면 다음 화면으로 이동한다.
- **결과:** 실제 정확한 알람 권한을 확인하지 못했는데도 권한 절차가 성공으로 끝날 수 있다. 새 테스트도 `unknown`을 `true`로 기대해 이 회귀를 고정한다(`test/release_audit/g1/g1_schedule_failure_test.dart:133-136`).
- **대조:** G1 #13은 MethodChannel 실패가 성공·권한 허용으로 둔갑하지 않고 granted/denied/unknown으로 구분되도록 요구한다. 화면을 막지 않는 정책이 필요하다면 `unknown`을 별도 UI 상태로 전달해야 하며, 성공 bool로 축약하면 안 된다.

### T11-02 — High — timestamp가 없는 기존 일정 예약은 DB 시각 일치 확인 없이 표시된다

- **상태:** **FIXED — `438a9b9`**
- **수정:** `schedule_expected_at`이 없거나 DB 트리거와 정확히 일치하지 않으면 표시하지 않는다. DB의 미래 일정은 현재 시각으로 재예약하고, 과거 일정은 폐기한다.
- **테스트:** 수정 전 `G1ScheduleNotifyTest` FAIL(옛 extra 없는 예약이 표시됨) → 수정 후 PASS.
- **위치:** `android/app/src/main/kotlin/com/hwani1103/shiftbell/ScheduleNotificationScheduler.kt:249-296`
- **조건:** 업데이트 전 만들어진 일정 PendingIntent라 `schedule_expected_at` extra가 없고, 그 뒤 같은 일정의 시각을 과거 쪽으로 변경했지만 옛 OS 예약 취소가 실패하거나 앱이 취소 전에 종료된다.
- **재현:** 현재 DB 트리거가 08:00인 일정 ID의 extra 없는 옛 09:00 예약을 09:00에 전달한다. `expectedAtMillis == null`이면 `trigger <= now`만 검사하므로 `matches=true`가 되어 알림을 표시한다.
- **결과:** DB 트리거와 옛 예약 시각이 다른데도 옛 시각에 새 DB 내용의 일정 알림이 뜬다. #5가 막으려는 “같은 ID 일정 변경 후 옛 예약 오표시”가 업데이트 호환 경로에 남는다.
- **대조:** v4 #5와 실행계획은 DB에서 다시 계산한 트리거와 Intent extra가 정확히 같을 때만 표시하도록 한다. timestamp 없는 기상 알람의 fail-open은 별도 정책이며, 일정 알림에 합치지 말라는 G1 상세 규칙과도 어긋난다.

### T11-03 — High — Native diff 키가 `day_offset` 변경을 놓쳐 override 원점을 잘못 보존한다

- **상태:** **FIXED — `438a9b9`**
- **수정:** Native desired/existing diff 키에 `day_offset`을 포함해 같은 시각·근무·타입이어도 기여 원점이 바뀌면 옛 슬롯을 유지하지 않는다.
- **테스트:** 수정 전 `G1GenerationEngineTest` FAIL(`day_offset=0` 행 잔존) → 수정 후 PASS. `review_fixture_additions.json`을 Kotlin/Dart 공통 fixture 테스트에서 함께 대조해 총 7개 생성 케이스를 양쪽에서 확인했다.
- **위치:** `android/app/src/main/kotlin/com/hwani1103/shiftbell/AlarmRefreshEngine.kt:65-95,181-223`
- **조건:** 같은 울림 시각·근무명·알람 타입을 유지한 채 기여 원점만 당일에서 다음날/전날로 바뀐다. 연속으로 같은 근무가 배정되고 같은 시각의 offset 템플릿이 있을 때 가능하다.
- **재현:** `2026-09-15 06:00 / A / type 1 / day_offset 0` fixed 행을 둔다. 새 원본은 9월 15일 미설정, 9월 14일 A이며 A의 `day_offset=1` 템플릿이 같은 9월 15일 06:00을 만든다고 한다. desired와 existing의 `key()`는 둘 다 `timestamp|A|1`이라 기존 행을 그대로 유지한다.
- **결과:** DB 행의 `day_offset`은 0으로 남는다. 이후 사용자가 이 알람을 삭제하거나 타입을 바꾸면 `_recordOverrideForUserChange`가 실제 원 배정일 9월 14일이 아니라 9월 15일을 `origin_date`로 기록하고, D12 변경 정리와 슬롯 매칭도 잘못된다.
- **대조:** override 슬롯 키는 `(slot_time, shift_type, day_offset)`이고 D12는 정확한 `origin_date`를 요구한다. `day_offset`은 timestamp에 이미 반영되어 항상 구분된다는 코드 주석은 같은 시각·같은 근무가 양쪽 기여에 존재할 때 성립하지 않는다.
- **보강 fixture:** `docs/release_audit/g1/review_fixture_additions.json`의 `OFFSET_ORIGIN_TRANSITION_SAME_VISIBLE_KEY`.

### T11-04 — High — OS 반영 재확인에서 DB 조회 실패를 성공 경로로 처리한다

- **상태:** **FIXED — `438a9b9`**
- **수정:** 예약/취소 직전 DB 조회·파싱 실패를 `FAILED`로 기록한다. 예약 검증 실패 때 낡은 payload를 예약하지 않고, 취소 검증 실패 때 현재 OS 예약을 먼저 지우지 않는다. 같은 ID의 유효한 미래 행은 취소 공백 없이 DB 값으로 갱신한다.
- **테스트:** 수정 전 `G1WakeSyncTest` FAIL(예약 결과 `SCHEDULED`, 스누즈 예약 소실) → 수정 후 두 경로 모두 `FAILED`, 스누즈 예약 보존, 실패 ID 기록 PASS.
- **위치:** `android/app/src/main/kotlin/com/hwani1103/shiftbell/AlarmWakeScheduler.kt:143-183,186-211`
- **조건:** 커밋 뒤 예약/취소 직전 DB 조회가 잠금·I/O·손상 등의 이유로 예외를 던진다.
- **재현 A:** 낡은 예약 작업의 `scheduleIfCurrent`에 조회 예외를 주입한다. 코드는 `found=null`로 바꾼 뒤 전달받은 옛 payload를 그대로 OS에 예약한다.
- **재현 B:** 같은 ID가 미래 snoozed 행으로 이미 갱신된 상태에서 늦은 `cancelIfGone`의 재조회가 실패하게 한다. 함수는 OS 예약을 먼저 취소하고 `row=null`로 간주한 뒤 실패 ID까지 지워 `CANCELLED`을 반환한다.
- **결과:** A는 삭제·변경된 알람을 다시 예약할 수 있고, B는 유효한 스누즈 예약을 없앤 뒤 재시도 표식도 남기지 않는다.
- **대조:** #27 계약은 예약 직전에 행 존재와 시각 일치를 확인하고, 늦은 취소에서 유효한 미래 행을 DB 시각으로 재예약하며, OS 반영 실패를 재시도 목록에 남기도록 한다. 조회하지 못한 상태는 이 조건을 충족한 것이 아니다.

### T11-05 — High — Flutter 재생성은 같은 입력에도 모든 fixed 행을 삭제·재삽입한다

- **상태:** **FIXED — `e6e679a`**
- **수정:** desired를 먼저 계산한 뒤 슬롯 시각·근무·`day_offset`·알람 타입이 같은 기존 fixed 행을 매칭해 ID와 행을 그대로 보존한다. 실제 diff만 이력·삭제·삽입 및 OS 취소/예약 대상으로 반환한다. 고정 now 주입점도 추가했다.
- **테스트:** 수정 전 `g1_alarm_regeneration_diff_test.dart` FAIL(기대 ID `1201`, 실제 `1202`) → 수정 후 같은 입력 2회 모두 ID `1201`, insert/delete/history/creation-log/OS-cancel 변화 0으로 PASS.
- **위치:** `lib/services/alarm_generation_service.dart:182-269`; 호출부 `lib/providers/alarm_provider.dart:163-230`, `lib/providers/schedule_provider.dart:267-341`
- **조건:** 영향 날짜에 이미 desired와 정확히 같은 fixed 행이 있고, 동일 근무를 다시 배정하거나 겹치는 일괄 배정으로 재생성 경로가 다시 호출된다.
- **재현:** T11 fixture `IDEMPOTENT_EXACT_EXISTING`의 ID 401 행을 DB에 넣고 `regenerateFixedAlarmsForDatesTxn`을 같은 schedule로 두 번 호출한다. 함수는 매번 해당 날짜의 미래 fixed를 전부 `superseded` 이력에 기록해 삭제하고 새 ID를 삽입한다.
- **결과:** 입력이 바뀌지 않았는데 ID가 계속 바뀌고 취소·재예약 및 생성/삭제 이력이 누적된다. DB 커밋과 MethodChannel 반복 사이의 예약 공백도 불필요하게 다시 열린다.
- **대조:** contracts §2와 #26은 같은 입력·now의 재갱신에서 insert/delete/history 0, ID 불변을 요구한다. 현재 Dart fixture 테스트는 순수 계산 목록만 비교해 JSON의 `expected_diff_first_run/second_run`을 실행하지 않으므로 이 결함을 검출하지 못한다.
- **보강 fixture:** `docs/release_audit/g1/review_fixture_additions.json`의 `DART_REGEN_IDEMPOTENT_EXISTING_ROW`.

### T11-06 — Medium — 진동 알람 다음에 무음 알람이 오면 이전 진동이 계속된다

- **상태:** **FIXED — `438a9b9`**
- **수정:** 새 알람 출력을 시작할 때 기존 vibrator를 먼저 취소하므로 무음 분기에서도 앞 회차 진동이 남지 않는다.
- **테스트:** 수정 전 `G1RingRoundTest` FAIL(무음 전환 뒤 vibrator 활성) → 수정 후 PASS.
- **위치:** `android/app/src/main/kotlin/com/hwani1103/shiftbell/AlarmPlayer.kt:40-56,77-83,313-329`; 인계 경로 `CustomAlarmReceiver.kt:75-86,131-148`
- **조건:** 진동 중인 알람 A에 응답하지 않은 채 무음 타입 알람 B가 도착한다.
- **재현:** A에서 `playVibration`으로 반복 진동을 시작한 뒤 B의 `playAlarmWithSettings("silent", ...)`를 호출한다. 함수 시작부는 MediaPlayer만 정리하고, vibrator 취소는 다음 `playVibration` 안에서만 한다. silent 분기는 아무 작업도 하지 않는다.
- **결과:** 활성 회차와 화면은 B로 넘어갔지만 A의 반복 진동이 남는다. B를 “무음”으로 설정한 사용자 의도와 실제 출력이 다르다.
- **대조:** S4는 진동·무음 및 알람 인계 동작을 함께 검증하도록 한다. 새 회차를 시작할 때 이전 출력 자원을 모두 정리해야 한다.

### T11-07 — Medium — 탭 숨김 채널 실패 뒤 로컬 상태와 Native 재부팅 상태가 갈라진다

- **상태:** **FIXED — `e6e679a`**
- **수정:** Native 동기화 성공 여부를 호출자에게 반환하고, 탭 notifier는 Native 반영 성공 뒤 prefs와 화면 상태를 갱신한다. prefs 저장 실패 때는 Native 값을 원래 상태로 되돌린다.
- **테스트:** 수정 전 `g1_schedule_tab_sync_test.dart` FAIL(예외 기대와 달리 정상 완료) → 수정 후 채널 실패 시 예외 전달 및 로컬 state/prefs 보존 PASS.
- **위치:** `lib/widgets/disable_tab_button.dart:68-70`, `lib/providers/tab_visibility_provider.dart:37-41`, `lib/services/schedule_notification_service.dart:95-125`
- **조건:** 사용자가 일정관리 탭 숨김을 확정한 순간 MethodChannel이 실패한다.
- **재현:** `cancelAllScheduleNotifications`이 `PlatformException`을 던지게 한다. Flutter prefs와 화면 state는 먼저 false로 바뀌고, 서비스는 채널 예외를 로그만 남기고 정상 반환하므로 탭은 숨겨진다. Native DP `schedule_tab_enabled`는 true이고 기존 OS 예약도 남는다.
- **결과:** 앱 UI에서는 탭을 껐지만 재부팅 수신기가 일정을 다시 예약할 수 있고 기존 예약도 표시될 수 있다. 다음 앱 시작 동기화 전까지 #5의 상태 불일치가 유지된다.
- **대조:** #5는 탭 on/off 시 DP 플래그와 예약 상태를 함께 맞추도록 한다. 실패를 호출자에게 반환해 UI 상태를 되돌리거나 즉시 재시도 가능한 상태로 남겨야 한다.

### T11-08 — Medium — 출퇴근 시각 한 번 저장에 revision이 중복 증가한다

- **상태:** **FIXED — `e6e679a`**
- **수정:** 외부 저장 반영 API가 통지 domain을 명시적으로 받도록 하고, 출퇴근 저장은 `shiftTimes`와 `workHoursSettings`를 각각 한 번만 통지한다. `shiftSchedule`은 증가시키지 않는다.
- **테스트:** 수정 전 `g1_revision_test.dart`가 필요한 `notify`/`notifyDomains` 주입점 부재로 컴파일 FAIL → 수정 후 `shiftTimes=1`, `workHoursSettings=1`, `shiftSchedule=0` PASS.
- **위치:** `lib/screens/work_hours_settings_screen.dart:350-357`, `lib/providers/schedule_provider.dart:27-35,82-90`
- **조건:** 출퇴근 시각 한 쌍을 저장하거나 초기화해 `saveShiftTimeRange` 한 트랜잭션이 성공한다.
- **재현:** `_persistShiftTime`이 `scheduleProvider.applyExternallyPersisted(saved)`를 호출하면 `shiftSchedule`과 `workHoursSettings` revision이 각각 1 증가한다. 이어 같은 함수가 `shiftTimes`와 `workHoursSettings`를 직접 증가시켜 `workHoursSettings`는 한 커밋에 2 증가한다.
- **결과:** G3 소비자는 한 번의 원본 변경에 중복 재계산할 수 있다. 동시에 `shift_durations`만 바뀐 저장이 `shiftSchedule` 변경으로도 통지된다.
- **대조:** contracts §3은 성공한 저장 경로에서 해당 영역 revision을 `+1` 하도록 한다. 상태 반영과 domain별 통지를 분리하거나 호출자가 이미 통지된 domain을 다시 올리지 않아야 한다.

## fixture 대조

- 메인 `docs/release_audit/g1/fixtures_draft_p1/`의 README와 JSON 2개는 `release/g1`의 `test/release_audit/g1/fixtures/` 사본과 SHA-256이 각각 일치한다.
- 독립 기대값 자체는 contracts §2의 오늘~+9일 창, 당일 > 전날 > 다음날 우선순위, 과거 제외, 창 밖 배정 기여, 미설정, 템플릿 0/조회 실패 구분, skip/set_type, custom·snoozed·activeRing 보호, D11·D12·rename·ABA를 포함한다.
- T11-03과 T11-05는 기존 JSON이 기대를 적었어도 현재 테스트 어댑터가 실행하지 못하는 상태 전이·DB diff다. 두 케이스를 `review_fixture_additions.json`에 독립 기대값으로 보강했다.

## 정적 대조에서 확인된 구현

- `2b82adc` Manifest는 `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, 정확한 알람 권한 상태 변경 액션을 `DirectBootReceiver`에 연결한다.
- P1 계산의 10일 울림 창과 기여 우선순위, 템플릿 조회 오류 전파, D11 정리 범위, D12 배정·템플릿·rename 기본 경로는 계약과 일치한다.
- 울림 회차 토큰, ongoing 제어 알림, DB 커밋 뒤 OS 호출 구조, `setAlarmClock` 단일 헬퍼, Locale.US 저장 포맷, 근무명 입력 검증과 2단계 rename은 코드에 연결되어 있다.
- 위 항목의 실제 전달·Doze·잠금화면·OEM 동작은 T12 및 S2~S4/S7/S8/S11/S13/S15/S16 증적 전에는 PASS로 판정하지 않는다.

## 결론

**FIXED / CODE_FROZEN `e6e679a`.** High 5건과 Medium 3건을 모두 수정했다. 수정 전 재현 FAIL과 수정 후 같은 테스트 PASS를 확인했으며, Kotlin 전체 `testDevDebugUnitTest`, Flutter 전체 211건, dev debug APK 빌드가 통과했다. `flutter analyze`의 유일한 error는 허용된 기존 `lib/web_main.dart`의 `dart:js_util` 1건이다. 에뮬레이터·실기기 검증은 실행하지 않았고 T12에서 계속한다.

## T11-FIX 확인 (Claude, 2026-09-14 — 수정 diff 가벼운 확인, 빌드·테스트 재실행 안 함)

대상 `2b82adc..e6e679a` (제품 코드 11개 파일 + 테스트). 방법: diff 전체 읽기 + 바뀐 함수의 호출부 대조. 판정: **CHANGES_REQUESTED(작은 후속 2건 + Low 1건)**.

| 항목 | 확인 |
|---|---|
| T11-01 | OK. `unknown`은 false. 권한 소개 화면은 경고 다이얼로그의 "계속"으로 넘어갈 수 있어 사용자가 갇히지 않음 |
| T11-02 | OK. extra 없으면 표시 안 함, DB 시각이 미래면 재예약 |
| T11-03 | OK. Kotlin diff 키에 `day_offset` 포함 — Dart(T11-05) 키와 일치 |
| T11-04 | 취소 경로(B) OK: 조회 후 유효 미래 행이면 취소 없이 교체 예약. **예약 경로(A)는 아래 C-02 재검토** |
| T11-05 | OK. `(slot_time, shift_type, day_offset)|alarm_type_id` 매칭으로 ID 보존, 실제 diff만 이력·OS 반영 |
| T11-06 | OK |
| T11-07 | 동작 OK(Native 먼저, 실패 시 상태·prefs 무변경). 아래 C-03(Low) |
| T11-08 | OK. shiftTimes 1·workHoursSettings 1(근무표 저장 결과 있을 때)·shiftSchedule 0 |

### C-01 — Medium — T11-04 수정이 `dismiss`의 DB 없음 경로에서 OS 취소를 막음 (회귀)

- 위치: `AlarmActionHelper.kt:43-47` `dismiss()` — `getWritableDatabaseWithRetry()`가 null(DB 미준비 또는 3회 열기 실패)이면 `AlarmWakeScheduler.cancelIfGone(context, null, alarmId)` 호출.
- 수정 전: null DB면 `cancelRaw` 후 CANCELLED. 수정 후: `db == null` → `recordFailure` + FAILED, **OS 예약을 지우지 않음**.
- 결과: 울리기 전 취소(`cancelled_before_ring`)를 눌렀는데 DB를 못 연 경우 예약이 남아 그대로 울림(수신 판정도 DB 열기 실패 시 RING). 주석("Native 알람 취소만 수행")과 반대.
- 요청: 이 경로는 사용자의 명시적 끄기이므로 DB 확인 없이 `cancelRaw`(실패 시 recordFailure) — `cancelIfGone`의 null 처리 대신 명시적 경로로. 테스트: null DB dismiss 뒤 OS 예약 없음.

### C-02 — Medium — 예약 직전 DB 조회 실패 시 예약을 보류하면 알람을 놓칠 수 있음 (T11-04 A 재검토)

- 위치: `AlarmWakeScheduler.scheduleIfCurrent` — `db == null`·조회 예외·row 파싱 실패 → FAILED, 예약 안 함.
- 근거: 옛 payload가 울릴 위험은 수신 시 `decideOnReceive`가 이미 막음(행 없음 → SKIP_NO_ROW, 시각 불일치 → 재예약·SKIP). 반면 예약 보류는 `retryFailed`(Guard·자정·엔진 실행) 전에 알람 시각이 오면 **안 울림** — 알람 앱에서 더 나쁜 쪽.
- 요청: 기상 알람 예약은 조회 실패 시 **예약을 진행하고 동시에 recordFailure**(재시도로 다시 확인). 명확한 SKIPPED_STALE(행 없음·시각 다름)만 버림. `MainActivity.scheduleNativeAlarm`의 FAILED → 채널 오류 흐름은 OS 예약 자체가 실패한 경우로 유지. 테스트: 조회 예외 주입 → 예약됨 + 실패 ID 기록, 수신 시 행 없음이면 SKIP.
- Codex가 이 판단에 반대하면 근거(수신 판정이 막지 못하는 경로)를 적고 유지해도 됨.

### C-03 — Low — 탭 표시 전환 실패가 사용자에게 안 보임

- `settings_tab.dart:631`, `disable_tab_button.dart:68`이 `setEnabled`의 `StateError`를 잡지 않음. 상태는 안 바뀌어 일관성은 맞지만 탭을 눌러도 아무 반응 없이 끝남.
- 요청(선택): 두 호출부에서 잡아 SnackBar로 실패 안내(ARB는 기존 `scheduleNotifyRegisterFailed` 재사용 가능 여부 확인). 출시 차단 아님.
