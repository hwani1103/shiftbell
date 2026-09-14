# 공통 계약 (G0 → G1/G2/G3, G4 선행 의미)

> 통합 담당자(Claude)만 수정. **T05 확정 (2026-09-14).** 실행계획 §3.3의 항목을 고정한다.
> 실제 함수명·파일 배치는 각 그룹이 기존 구조를 읽고 최소 변경으로 정하되, **의미는 이 문서를 따른다.**
> 이 문서와 다른 동작이 필요하면 구현하지 말고 자기 그룹 `integration_requests.md`에 적는다.

## 0. 기준

| 항목 | 값 |
|---|---|
| 기준 커밋 (T05, `dev`) | `c0b2e73` (merge: G0 → dev) — release/g2·g3 시작점. **G1은 `94ff08f`**(R0 교차 리뷰 반영 G0 재병합, 2026-09-14)에서 시작. 계약 의미 변경은 §5(시작 멈춤·DB 경로)뿐 |
| 포함 | G0 제품 `637b56a` + 테스트 `c06ffea` + 문서 + 공통 인터페이스 `lib/providers/data_revision_provider.dart` |
| G0 상태 | 자동 테스트 PASS, **S1 실기기(T04) 미통과 → G1/G2/G3는 `PROVISIONAL / G0 실기기 미통과` 상속** (실행계획 §2.2). T04 결과로 G0 계약이 바뀌면 통합 담당자가 각 그룹을 동결·재기준화 |
| 결정 | D1~D12 확정(실행계획 §4). REPAIR-REJECT = 사용자 결정 A(`g0/test_results.md` 6장) |

---

## 1. DB

### 1.1 스키마 v24
- 버전 값 3곳이 항상 같아야 함 (빌드 검사 `checkDartKotlinSync`): `DatabaseHelper.kt` `DATABASE_VERSION`, `database_service.dart` `version:`, `assets/db/migrations.json` `"targetVersion"`.
- **G1/G2/G3/G4는 스키마를 바꾸지 않는다.** 스키마 결함·추가 필요는 통합 담당자(G0)에게 요청.
- 신규 테이블 `alarm_overrides` (v4 #31, D10):

| 컬럼 | 형 | 규칙 |
|---|---|---|
| `id` | INTEGER PK AUTOINCREMENT | |
| `slot_time` | TEXT NOT NULL | `yyyy-MM-dd'T'HH:mm:ss`, **Locale.US**, 초 `00`. 밀리초 접미사 금지 |
| `shift_type` | TEXT NOT NULL | 슬롯의 근무명 |
| `day_offset` | INTEGER NOT NULL DEFAULT 0 | CHECK IN (-1, 0, 1) |
| `action` | TEXT NOT NULL | CHECK IN ('skip', 'set_type') |
| `alarm_type_id` | INTEGER | `set_type`이면 NOT NULL, `skip`이면 NULL (CHECK) |
| `origin_date` | TEXT NOT NULL | 그 알람을 만든 배정일 `yyyy-MM-dd` |
| `origin_shift` | TEXT NOT NULL | 그 배정일의 근무명 |
| `created_at` | TEXT NOT NULL | |

  - UNIQUE `(slot_time, shift_type, day_offset)` = 슬롯 키. 같은 슬롯을 다시 쓰면 INSERT가 실패하므로 **G1은 upsert(교체)로 쓴다.**
  - FK 없음. `alarm_type_id`가 가리키는 타입이 사라진 경우의 재생·표시 처리는 G1(#31), 복원 시는 G4(#19).

### 1.2 SQL 단일 원본 `assets/db/migrations.json` (format 1)
- `migrations`: v2..target 전 구간, 버전별 SQL 배열. **기존 항목 수정/삭제 금지.**
- `repair`: 최신 스키마의 비파괴 최종 형태. 허용 3종(`CREATE TABLE IF NOT EXISTS`, `CREATE [UNIQUE] INDEX IF NOT EXISTS`, `ALTER TABLE t ADD COLUMN c`), CREATE TABLE 선행, 대상 테이블 CREATE 필수. 위반 시 파싱 단계에서 예외.
- 한 항목 = SQL 한 문장(`;` 금지). 실행기 쌍 `lib/services/db_migration_runner.dart` ↔ `DbMigrationRunner.kt`.

### 1.3 열기·업그레이드·오류 전파
| 단계 | Dart | Native |
|---|---|---|
| 신규 생성 | `_onCreate` (직접 작성) | **예외** — 생성 안 함 |
| 업그레이드 | sqflite `onUpgrade` → 실행기 (EXCLUSIVE 잠금 안에서 버전 재확인) | `onUpgrade` → 잠금 안 `db.version` 재확인 후 실행기 |
| 다운그레이드 | 예외(시작 실패 화면) | 예외 |
| 열기 | `onOpen` → repair + 프리셋 알람 타입 비었으면 재삽입 | `onOpen` → repair (SQL 원본 로드 실패 시만 복구 건너뜀) |

- 실패는 삼키지 않음 → 트랜잭션이 버전까지 롤백 → 다음 접근 때 재시도.
- Native 게이트(`DatabaseHelper.get*DatabaseWithRetry`): 파일 없음·버전 0·디스크>Native → `null`, 디스크<Native → 열면서 마이그레이션, 같음·확인 실패 → 진행. **`null`이면 호출부의 기존 fail-safe를 유지**(이 계약은 변경 없음).

### 1.4 트랜잭션과 OS 호출
- Native 쓰기: 게이트에서 받은 싱글턴 연결의 `beginTransaction()`(EXCLUSIVE). Dart 쓰기: `DatabaseService.instance.database`의 `transaction`.
- **트랜잭션 안에서는 원본 읽기·계산·DB 쓰기만. AlarmManager 등 OS 반영은 커밋 후.** (#16/#27, G1이 확정 구현)

## 2. 시간/알람 (G1 구현, G4·G3 소비)

- **창:** 실제 울림일 R ∈ [오늘, 오늘+9]. `kAlarmRefreshWindowDays` = `DAYS_AHEAD` = 10 (빌드 검사). "모든 배정일의 10일 전 생성"으로 되돌리지 않음(D1-a).
- **기여:** 울림일 R ← R의 당일 템플릿(offset 0), R+1 배정의 전날 템플릿(-1), R-1 배정의 다음날 템플릿(+1). 같은 울림 시각 충돌 우선순위 **당일 > 전날 기여 > 다음날 기여**. 지금 이전 시각 제외. 규칙·불규칙(P1, D1) 동일 계산.
- **입력:** 템플릿 조회 성공 후 0개 = 유효한 빈 결과(옛 fixed 정리). 조회 실패는 예외로 전파 — 빈 결과로 바꾸지 않음. 불규칙 빈 pattern은 손상이 아님.
- **now 주입:** 생성 계산은 now를 인자로 받는다. Dart·Kotlin 계산은 같은 fixture로 비교 테스트한다(쌍: `alarm_generation_service.dart` ↔ `AlarmRefreshEngine.kt`).
- **저장 시각 문자열:** 새로 쓰는 DB 저장값(`alarms.date`, `alarm_overrides.slot_time`, 이력 등)은 `yyyy-MM-dd'T'HH:mm:ss`, Locale.US. 표시용 로케일과 분리(#17). 이미 잘못 저장된 값은 실패로 보고하고 형식 변경만으로 복구됐다고 하지 않음.
- **보호 대상 (갱신·정리가 건드리지 않음):** `custom`, 미래 `snoozed`, **현재 울리는 알람(activeRing)**. activeRing 행이 fixed일 수 있으므로 `type` 필터만으로 판단 금지. 현재 activeRing 원천: Native `RingingAlarmTracker`(`alarm_state.currently_ringing_alarm_id`) — #3에서 회차 토큰으로 확장하는 것은 G1.
- **개별 예외 적용:** 계산 결과에 override 적용 후 diff. `skip` = 생성 제외, `set_type` = `alarm_type_id` 대체. 키는 1.1 슬롯 키.
  - D11: `slot_time`이 30일 이상 지난 override만 정리. 영구 이력(`alarm_history`/`alarm_creation_log`)에는 절대 적용 안 함.
  - D12: 배정일 D의 근무가 바뀌면 `origin_date = D` 예외 삭제, 근무 S의 템플릿이 바뀌면 `origin_shift = S`인 미래 예외 삭제 — 원본 변경과 **같은 트랜잭션**. 근무명 rename은 `shift_type`·`origin_shift`를 같은 트랜잭션에서 변경. `A→B→A` 되돌림 테스트 필수.
- **멱등성:** 같은 입력·now의 재갱신은 추가/삭제/생성이력 0, ID 불변. 알람 0개여도 자정 Guard 유지.
- **정책 도입 1회 강제 갱신(P1):** 신규 Native prefs 키 `alarm_state.refresh_policy_version`(int, 소유 G1) — **첫 강제 갱신 성공 후에만** 기록.
- **OS 반영 재확인:** 예약 직전 행이 없거나 낡았으면 예약 버림 / 취소 직전 행이 없으면 **항상 취소** / 늦은 취소 시 같은 ID가 유효한 미래 행이면 최신 DB 시각으로 재예약. 수신 Intent의 예정 시각과 DB 시각은 **정확 비교**(1분 허용 금지).
- **예약 API:** 기상 알람(모든 등록 경로)은 `setAlarmClock`(#20). 일정 알림·수면 감지는 이 정책으로 바꾸지 않음.

## 3. 변경 통지 (G1 → G3)

- 공통 선언: `lib/providers/data_revision_provider.dart` — `dataRevisionProvider(DataDomain)` (T05 기준 커밋에 포함, 동작 없음).
- **G1 의무:** 아래 원본을 저장하는 모든 경로에서, **커밋/저장 성공 뒤에만** 해당 영역 revision을 `+1`. 실패·롤백이면 올리지 않음.
  | DataDomain | 원본 |
  |---|---|
  | `shiftSchedule` | `shift_schedule` (패턴·배정·근무명·색상) |
  | `overtime` | `date_overtime` |
  | `workHoursSettings` | SharedPreferences `work_hours_*`, `shift_schedule.shift_durations` |
  | `shiftTimes` | `condition_shift_times` |
- **G3 의무:** 컨디션·수면 계산 provider가 필요한 영역을 watch해 재계산. 재계산 멱등, 구독 해제·중복 구독·mounted 검사. G3는 이 원본들의 저장 로직을 따로 만들지 않음.
- 새 영역이 필요하면 enum 추가를 통합 담당자에게 요청(두 그룹이 같은 선언을 써야 하므로 직접 추가 금지).

## 4. 공유 (G2 구현, G1·G4 연결)

- **로컬 상태(영속, Flutter SharedPreferences, 소유 G2):** 기존 `friend_share_enabled`(bool), `friend_share_my_name`(String). G2가 추가하는 공유 의도 상태(off/active/stop_pending), dirty, generation 키는 `friend_share_` 접두사로 만들고 g2/handoff에 등록부 형식으로 기록.
- **상태 의미 (실행계획 G2 "공유 상태 계약" 그대로):**
  - 중지하면 로컬은 즉시 off, 서버 중지 성공 확인까지 `stop_pending` 영속. 재시작 후 임의로 active 복원 금지.
  - generation은 **새 공유 시작 회차**에만 증가. 이름·근무표 정상 수정마다 올리지 않음. 각 진입점 + **실제 set 제출 직전**에 현재 의도·회차 검사.
  - 제출 순서는 단일 큐. 앞선 offline write의 ACK를 무한정 기다려 뒤의 stop을 막지 않음. Future timeout은 이미 제출된 write를 취소하지 않음을 전제로 설계.
  - 실패한 시작·이름 변경·수정은 실패/pending을 사실대로 표시하고 dirty 유지 → 앱 시작·재개·재연결 때 **현재 상태로** 재시도.
  - 공유할 필드가 바뀐 경우만 업로드. 공유 대상 필드를 늘리지 않음.
- **G2가 제공할 진입점(이름은 G2가 정해 handoff에 기록, 연결은 T10에 통합 담당자):** ① 앱 시작 ② 앱 재개 ③ 네트워크 재연결 시 재시도 ④ **복원 완료 후**(G4 호출): 현재 UID·generation·상태 유지, active면 dirty 재업로드, stop_pending이면 중지 재시도 유지.
- **백업:** 공유 상태 키는 백업에서 제외 대상(#25). 제외 구현은 G4, 키 목록 확정은 G2.
- D7: 앱 측 상태 머신까지만. tombstone/rules 서버 강제는 T16 사용자 결정 후. D8: S12 조사만, Firebase 프로젝트 생성·운영 설정 변경 금지.
- `firebaseReady`는 앱 시작 후 늦게 true가 될 수 있음(초기화 10초 상한, 5장).

## 5. 초기화 (V4)

- `lib/main.dart` `_initializeApp()`:
  - **필수**(실패 → 시작 실패 화면): `initializeDateFormatting(ko_KR, en_US)`, `DatabaseService.instance.database`, `AlarmService().initialize()`.
  - **선택**(예외 로그, 10초 넘으면 기다리지 않음): `initFirebase`(이미 `firebaseReady`면 생략), `AdService.warmUp`. `MemoCategoryClassifier.ensureLoaded`, `GoogleFonts.pendingFonts`는 await 없이 오류만 로그.
- `lib/screens/startup_gate.dart` `StartupGate<T>`: 빈 화면 → 15초 넘으면 준비 중 → **45초 넘게 끝나지 않으면 멈춤(다시 시도 버튼)** → 실패 시 안내 + 다시 시도 → 성공 시 builder. 다시 시도는 실패·멈춤 상태에서만, 늦게 끝난 옛 시도 결과는 무시. 릴리스 빌드는 원문 미표시. (R0-02 반영, 2026-09-14)
- **DB 경로(R0-01, 2026-09-14):** Android에서는 `getDeviceProtectedStoragePath` 조회가 실패하면 **다른 경로로 대체하지 않고 예외** → 시작 실패 화면. Native와 DB가 갈라지는 것을 막기 위함. Android가 아닌 환경(호스트 테스트)만 일반 경로. 테스트 스위치 `DatabaseService.debugIsAndroidOverride`.
- **`DatabaseService.instance.database`(R0-04):** 첫 호출자를 포함한 모든 호출자가 같은 초기화 Future를 기다림. 진행 중에 다시 불러도 새로 열지 않음, 실패하면 다음 호출이 처음부터 다시 시도.
- **필수 단계를 추가하는 그룹은 그 단계가 여러 번 불려도 안전해야 함.** 선택 서비스는 늦게 준비될 수 있음을 전제.
- `main.dart`는 병렬 구간에서 G1 소유. G2/G3의 진입점 연결은 `integration_requests.md`로.

## 6. 복원 연동 (G4 구현 — 의미만 고정, G1/G3는 구현하지 않음)

- 잠금: DP prefs 토큰 + **Native 프로세스 메모리의 소유 토큰**으로 판정, Dart가 MethodChannel로 소유권 전달. 시간 경과만으로 살아 있는 잠금을 무시하지 않음. 현재 단일 프로세스 전제(Manifest에 `android:process` 없음).
- 복원 중 **허용**: 알람 재생·끄기·스누즈·타임아웃. **차단/연기**: 갱신 엔진, Guard 재예약, 수면 쓰기, 일정 재예약, 자동백업, 앱 UI 쓰기. 복원 owner 자신의 최종 재조정은 gate 통과.
- 진행 중 스누즈·activeRing 행은 **기존 ID 유지**, ID 충돌 시 새 ID는 백업 custom 쪽. 재생 설정은 복원 전 스냅샷 우선.
- **G1/G3 의무(지금):** 빈 gate 함수·스텁을 만들지 않는다. 대신 **DB·prefs·OS에 쓰는 코드를 새로 만들거나 트리거를 바꾸면** 자기 handoff의 "writer 목록"(파일·함수·쓰는 대상·트리거·실행 컨텍스트)에 기록 → T09/G4 전수 목록 입력.
- G4 주의(T03 인계): REPAIR-REJECT 상태에서 만든 백업은 옛 friends 컬럼을 담아 현재 `restoreAll`에서 복구 전체가 실패할 수 있음 → #19 복원 전 테이블·컬럼 검증에서 처리.

## 7. 저장소 — 키 등록부 (T05 조사 기준)

> Flutter `SharedPreferences`와 Native `alarm_state` 등은 **서로 다른 파일**. Native가 Flutter 값을 읽을 때는 파일 `FlutterSharedPreferences`, 키 `flutter.` 접두사.
> **백업(현재)**: `backup_service.exportAll`은 Flutter prefs **전체 키**를 내보내고 `restoreAll`이 전부 다시 씀(복구 후 `permissions_requested`만 false로 강제). Native prefs는 백업 안 됨. 제외 목록 설계는 G4(#2/#25).
> 새 키를 만들면 이름·소유·형·기본값·백업 포함 여부·실패 시 동작을 자기 handoff에 적고, 통합 담당자가 T10/T17에 이 표에 합친다. 다른 그룹 키를 다른 의미로 재사용 금지.

### 7.1 Flutter SharedPreferences
| 키 | 형 | 쓰는 곳 | 병렬 구간 소유 | 백업(현재) | 비고 |
|---|---|---|---|---|---|
| `permissions_requested` | bool | permission_intro_screen, main, splash, restore_backup_screen | G1 (restore 쪽 G4) | 포함, 복구 후 false 강제 | |
| `calendar_theme_id` | String | calendar_theme_provider | 미배정(수정 필요 시 통합 담당자 배정) | 포함 | |
| `schedule_management_bg_color_index` | int | schedule_background_provider | G1 | 포함 | |
| `schedule_tab_enabled` / `condition_tab_enabled` | bool | tab_visibility_provider | G1 | 포함 | Native `SleepWidgetProvider`(G3)가 `flutter.condition_tab_enabled` 읽기 전용 |
| `work_hours_period_mode` | String | work_hours_settings_provider | G1 | 포함 | G3 소비, 변경 통지 `workHoursSettings` |
| `work_hours_payday_cutoff_day` | int | 〃 | G1 | 포함 | 〃 |
| `work_hours_cutoff_anchor` | String | 〃 | G1 | 포함 | 〃 |
| `work_hours_cutoff_is_period_start` | bool | 〃 (legacy 읽기) | G1 | 포함 | |
| `work_hours_shift_change_as_ot` | bool | 〃 | G1 | 포함 | 〃 |
| `all_teams_my_team` / `all_teams_offsets` | String | all_teams_setup_screen, all_shifts_view, settings_tab | G1 | 포함 | |
| `all_teams_names` | List<String> | 〃 | G1 | 포함 | |
| `schedule_etc_icon_rotation_counter` | int | schedule_management_tab | G1 | 포함 | |
| `backup_last_data_version` | int | backup_watcher | G4 | **포함(휘발 값)** | #2에서 재설계 |
| `backup_last_saved_at` | String | backup_watcher | G4 | **포함(휘발 값)** | #2 |
| `friend_share_enabled` | bool | friend_sync_service | G2 | **포함 → #25 제외 대상** | |
| `friend_share_my_name` | String | friend_sync_service | G2 | 포함 (제외 여부 G2 결정) | |
| `notified_update_version` | int | update_service | 미배정(G5 후보) | 포함 | |
| `update_check_last_checked_at` | int | update_service | 〃 | 포함 | |
| `release_note_seen_version` / `release_note_last_seen_app_version` | String | update_service | 〃 | 포함 | |
| `welcome_popup_shown` / `shift_assign_tutorial_shown` / `condition_tab_tutorial_shown` / `schedule_tab_tutorial_shown` | bool | onboarding_info_popups | 미배정(G5 후보) | 포함 | |
| (웹 localStorage) `shiftbell_last_owner_id` | String | web_main | G2 | 해당 없음 | |

### 7.2 Native SharedPreferences
| 파일 (저장소) | 키 | 형 | 쓰는 곳 | 소유 | 백업 |
|---|---|---|---|---|---|
| `alarm_state` (Device Protected) | `last_alarm_refresh` | long | AlarmRefreshEngine, AlarmRefreshUtil, DirectBootReceiver, MainActivity | G1 | 안 됨 |
| 〃 | `last_boot_time`, `last_checked_boot_time` | long | DirectBootReceiver, AlarmRefreshUtil | G1 | 안 됨 |
| 〃 | `refresh_lock_owner`, `refresh_lock_until` | 〃 | RefreshLockManager | G1 | 안 됨 |
| 〃 | `currently_ringing_alarm_id` | int | RingingAlarmTracker | G1 (#3 확장) | 안 됨 |
| 〃 (T10 등록, G1 9b8a586) | `currently_ringing_round` | long | RingingAlarmTracker — 활성 울림 회차, 없으면 0(이전 버전 값) | G1 #3 | 안 됨 |
| 〃 (T10 등록) | `ring_counter` | long | RingingAlarmTracker — 누적 회차, **초기화 안 함** | G1 #3 | 안 됨 |
| 〃 (T10 등록) | `os_sync_failed_alarm_ids` | StringSet | AlarmWakeScheduler — OS 반영 실패 알람 ID, 성공·할 일 없음 시 제거 | G1 #27 | 안 됨 |
| 〃 (T10 등록) | `refresh_policy_version` | int | AlarmRefreshEngine.markRefreshed(성공 뒤에만, 현재 값 1) / AlarmRefreshUtil(낮으면 강제 갱신) | G1 #26 P1 | 안 됨 |
| 〃 (T10 등록) | `schedule_tab_enabled` | bool(기본 true) | ScheduleNotificationScheduler — 탭 숨김/복원 채널·앱 시작 동기화(Flutter prefs `schedule_tab_enabled`와 짝) | G1 #5 | 안 됨 — **G4 복원 후 앱 시작 동기화로 재설정** |
| `sleep_detection_state` (Device Protected) | `first_off_sample_at`, `reject_hour_count_<h>`, `reject_hour_last_at_<h>` | long/int | SleepDetectionReceiver | G3 | 안 됨 |
| `backup_prefs` (**일반 저장소**, DP 아님) | `last_backup_uri` | String | MainActivity | G4 | 안 됨 |

- **T10 소유권 결정(2026-09-14)**: §3.1 목록 밖이던 `lib/services/permission_service.dart`, `lib/widgets/permission_warning_banner.dart`(G1 #13), `CalendarWidgetScheduleResolver.kt`(G1 #17), `lib/providers/overtime_provider.dart`(contracts §3 OT 통지)를 **G1 소유**로 확정 — release/g2·g3 변경 경로와 교집합 0건.
- 위 `RefreshLockManager.kt`·`AlarmRefreshUtil.kt`·`AlarmGuardReceiver.kt`처럼 실행계획 §3.1 목록에 파일명이 직접 없는 알람 계열 Native 파일은 **G1 소유**로 확정. 공유 위젯 resolver(`CalendarWidgetScheduleResolver.kt`)는 수정이 필요하면 G1로 배정.

## 8. 테스트 경계와 작업 환경

- SQL 원본 주입: Dart `DbMigrationScript.parse`/`loadFromAssets(bundle)`, Kotlin `DbMigrationScript.parse` + `overrideForTest`.
- **Gradle 단위 테스트에는 flutter 자산이 합쳐져 Native `DbMigrationScript.load`가 실제 원본을 읽는다** → Native DB 테스트는 onOpen repair가 실제로 돈다는 전제로 작성.
- **Robolectric SQLite는 3.8.7** — `DROP COLUMN` 등 최신 문법, `PRAGMA index_list`의 origin/partial 없음.
- DB fixture: `tool/g0/build_fixtures.py` + `test/release_audit/g0/`(역사 DB 23개, 기대 데이터, 기준 구조 `v24_oncreate_schema.json`). 공통 도구 Dart `g0_support.dart`, Kotlin `G0TestSupport.kt` 재사용 가능.
- 초기화: `StartupGate(initialize:, slowThreshold:)` 주입.
- **새 worktree 준비:** 추적 제외 파일 복사 필요 — `android/gradlew`, `android/gradlew.bat`, `android/gradle/wrapper/gradle-wrapper.jar`(T05에서 g1~g3에 복사함). 처음에 `flutter pub get`(l10n 생성 포함). release 서명이 필요한 작업만 `android/key.properties` 별도 복사.
- **이 PC에서 Gradle은 `sh ./gradlew …`로 실행**(Git Bash의 `gradlew.bat`·`cmd /c` 실패). 빌드·테스트는 한 번에 하나, 끝나면 `sh ./gradlew --stop`.
- 기록 문서(`docs/release_audit/**`)는 메인 폴더 사본만 쓴다. worktree에는 제품·테스트 코드만.

## G4/G5 추가 키 (2026-09-14)

> §7.2 등록부 보충 - G4 `1c5d403`, G5 `06f450b`.

| 저장소 | 키 | 형 | 소유 | 백업 | 의미 |
|---|---|---|---|---|---|
| Native DP prefs `restore_state` | `restore_lock_token` | String | G4 | 안 됨 | 살아 있는 복원 토큰(메모리 토큰과 같을 때만 유효) |
| Native DP prefs `restore_state` | `restore_interrupted` | bool | G4 | 안 됨 | 죽은 잠금을 정리했음(앱 시작 시 소비) |
| Native DP prefs `restore_state` | `restore_deferred_writers` | StringSet | G4 | 안 됨 | 복원 중 미뤄진 writer 이름(진단용) |
| Native DP prefs `restore_state` | `ring_snapshot_<alarmId>` | String(JSON) | G4 | 안 됨 | 복원 전 재생 설정(sound_file·volume·vibration_strength·duration) |
| Flutter prefs | `backup_last_content_hash` | String | G4 | 제외 | 마지막 성공 백업 내용 지문 |
| DP 파일 `restore_work/job.json`, `copy_<id>.json` | - | 파일 | G4 | - | 복원 단계 기록·작업 사본 |
| 백업 제외 설정 | `backup_last_*`, `permissions_requested`, 업데이트 안내 4키, `shiftbell_last_owner_id`, 친구공유 7키 | - | G4/G2 | 제외 | `lib/services/backup_policy.dart` |
