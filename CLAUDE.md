# Shiftbell (교대시계) 프로젝트 가이드

교대 근무자를 위한 알람/근무일정 앱. Flutter + Kotlin Native.
Play Store 배포중 — **현재 운영 버전 `v1.0.22+24`** (태그 `v1.0.22` = `main` = 커밋 `ca82d69`).
dev에는 출시전 감사(G0~G5)가 반영된 `1.0.23+25`가 준비 중.

> 값(버전/개수/경로)을 인용하기 전에 실제 파일을 한 번 확인하세요.
> 2026-09-14에 루트의 옛 설계/검토 문서 20개를 정리해 핵심만 이 문서 **"설계 기록"** 절로 옮겼습니다.
> 코드 주석에 남아 있는 옛 문서 이름(`컨디션매니저_설계.md`, `백업복구_설계.md`, `DB_스키마_변경_가이드.md` 등)은
> 더 이상 존재하지 않으니 이 문서의 해당 절을 보세요.

---

## 브랜치 / 릴리스 규칙

| 브랜치 | 역할 |
|--------|------|
| `main` | **배포된 코드만.** 릴리스할 때만 dev에서 병합하고 `vX.Y.Z` 태그를 붙임 |
| `dev` | 기본 작업 브랜치. 다음 버전 작업은 전부 여기서 |

- 릴리스 절차: dev에서 버전 bump → 빌드/검증 → `main`에 병합 → `git tag -a vX.Y.Z` → push (태그도 같이 push)
- **버전은 두 곳을 같이 올려야 함**: `pubspec.yaml`의 `version:`, `android/app/build.gradle.kts`의 `versionCode`/`versionName`
- 배포·공휴일 추가 절차: `업데이트_가이드.md` (운영 빌드는 광고 ID 주입 필수 — 아래 "광고" 참고)

---

## 기술 스택

- **Flutter (Dart)** + **Riverpod** 상태 관리
- **Kotlin Native (Android)** — 알람 실행, 홈 화면 위젯, 부팅/자정 갱신, 수면 감지, 복원 잠금
- **SQLite (sqflite)** — **Device Protected Storage**에 저장 (잠금 해제 전에도 알람이 동작해야 하므로)
- **MethodChannel** — `com.hwani1103.shiftbell/alarm` (⚠️ `com.example`이 아님)
  - 채널 이름은 `lib/constants/platform_channel.dart`의 `kAlarmChannel` **하나만** 사용할 것. 리터럴 문자열 금지
- **Firebase** (프로젝트 `shiftbell-29f31`, prod·dev 공용) — Firestore + Anonymous Auth + Analytics
  - Analytics는 `FirebaseOptions`만으로 안 되고 `google-services.json`(prod/dev 두 패키지 등록) +
    `com.google.gms.google-services` Gradle 플러그인이 필요함(한 번 뺐다가 `E FA: Missing google_app_id`로 다시 붙임)
  - dev flavor는 dev 앱 ID(`DefaultFirebaseOptions.androidDev`)로 초기화하고 **Analytics 수집을 끔** — 운영 DAU 오염 방지(#29)
  - `friend_schedules` 친구 근무표(익명 UID 문서) / `app_config` 업데이트 안내(읽기 전용) / `health_tips` 컨디션 탭 팁(읽기 전용, list 허용)
  - 규칙: `firestore.rules` — 콘솔 배포는 사용자가 직접 함. 규칙은 소유권·list 차단만 있고 필드 형식·크기 검증은 없음(D7로 이번 출시 미채택)
- **AdMob** 배너 — 실제 ID는 소스에 없음(아래 "광고")
- **i18n** — 한국어(원본) / 영어. `lib/l10n/app_ko.arb`(템플릿) + `app_en.arb`
  - `lib/l10n/generated/`는 **생성물이라 커밋 대상 아님**
  - 화면 코드에서는 `context.l10n.<key>`. 새 문자열은 두 ARB에 같은 키로 추가

### 빌드 flavor (dev / prod)

dev는 `applicationId`에 `.dev` 접미사가 붙은 완전히 다른 앱이라 DB/설정이 분리되고 스토어 설치본을 덮어쓰지 않음.

```bash
flutter install --release --flavor dev        # 테스트 설치
flutter build appbundle --release --flavor prod --dart-define=ADMOB_BANNER_ID=<배너 ID>   # 스토어 배포용
```

> ⚠️ **flavor 없이 `flutter run`/`install`을 돌리면** 서명이 달라 스토어 설치본이 "Uninstalling old version..."과 함께
> **삭제**될 수 있음. 반드시 flavor를 지정할 것. flavor 없이 빌드하면 `appFlavor`가 비어 prod 분기(광고·Analytics)도 안 탐.

### 광고 (2026-09-14 G5 #6)
`lib/constants/ad_config.dart` — 배너 단위 ID는 **prod flavor + release**에서만 `--dart-define=ADMOB_BANNER_ID`로 주입,
주입 안 하면 광고 요청 자체를 안 함. 앱 ID는 `build.gradle.kts`의
`manifestPlaceholders["admobAppId"]` ← Gradle 속성 `ADMOB_APP_ID`(없으면·dev는 구글 테스트 앱 ID).
**prod release 빌드는 두 ID가 모두 실제 값이 아니면 `checkProdAdIds`가 빌드를 실패시킴**(교차 검토 X-13 — 앱 ID만 빠지면
테스트 앱 ID로 실제 배너를 요청하는 상태가 됐었음). Analytics 초기 수집은 Manifest `firebase_analytics_collection_enabled`
(dev false / prod true, placeholder)로도 막음(X-14).
광고 영역 파란 틴트는 debug 빌드에서만. 개발 중 실제 ID 사용 금지(무효 트래픽으로 계정 정지 위험).

---

## 구현된 기능

### 알람
- 규칙적/불규칙 근무 스케줄, 근무별 알람 템플릿 (근무당 최대 **5개** — `kMaxAlarmTemplatesPerShift`)
- 알람은 근무 배정일 기준 **전날/당일/다음날**(`day_offset`, -1/0/1). 같은 실제 시각에 겹치면 하나만(당일 > 전날 기여 > 다음날 기여)
  — 계산은 `lib/services/alarm_generation_service.dart` ↔ `AlarmRefreshEngine.kt`가 **동일하게 유지**(공통 fixture 테스트 있음)
- **10일치** 롤링 자동 생성/갱신 (`kAlarmRefreshWindowDays` ↔ Kotlin `DAYS_AHEAD`). 불규칙 근무도 같은 계산(#26 P1)
- 개별 알람 삭제·타입 변경은 `alarm_overrides`에 저장돼 자동 갱신이 원복하지 않음(#31). 배정일·템플릿이 바뀌면 관련 예외 삭제(D12), 30일 지난 예외만 정리(D11)
- 갱신 엔진: 잠금 트랜잭션 안에서 읽기→계산→쓰기, **OS 예약은 커밋 뒤** `AlarmWakeScheduler.kt` 한 곳(`setAlarmClock`)에서만.
  예약 직전 DB 재확인, 실패 ID는 기록 후 다음 트리거에 재시도. 수신 시 예정 시각과 DB 시각 정확 비교
- 잠금 화면(`AlarmActivity`) / 해제 상태(`AlarmOverlayService`), 울림 회차(`RingingAlarmTracker`) 기준 종료·자동 타임아웃(AlarmManager 예약)
- 울리는 동안 제어 알림 7777(5분 후 / 알람 끄기), 20분 전 사전 알림, 스누즈 5분
- 알람음 7종 + 제조사 시스템 알람음, 볼륨 보정(`VolumeCalibration.kt`)
- 알람 이력/생성 로그 **영구 보존** (`alarm_history`, `alarm_creation_log`)
- 부팅(잠금 해제 전·후), 앱 업데이트, 정확한 알람 권한 허용 시 재조정(`DirectBootReceiver`)
- 상세: `docs/release_audit/g1/handoff.md`

### 달력 / 근무
- 달력 탭, 전체 근무표(`all_shifts_view`, 전체 조 설정은 다시 편집 가능), 날짜별 근무 변경
- **달력 테마 9종** (`lib/models/calendar_theme.dart`) — **앱에만 반영, 홈 위젯은 라이트 고정**(아래 설계 기록 참고)
- 근무명 색상 직접 지정(`effectiveShiftColors()`), 근무명 입력은 쉼표·"미설정"·"없음"·중복 차단, 맞교환 rename 지원(#11/#12)
- 날짜별 **메모**, **OT/특근**, 근로시간·급여 산정(`work_hours_calculator.dart`)
- 공휴일 표시 (`holiday_util.dart` + `CalendarWidgetHolidays.kt` — **둘 다 같이 갱신**, 영어 로케일에서는 공휴일 표시 안 함)

### 홈 화면 위젯
- `CalendarWidgetProvider.kt` — 달력 + 근무색 + 메모. 라이트 고정 렌더링
- `SleepWidgetProvider.kt` — 수면 위젯(아래 수면 기록)

### 일정관리 탭 / 카테고리 자동분류
- `schedule_management_tab.dart` — 세로 시간축에서 시각을 골라 일정 생성/수정. `date_schedules`(v20, `date_memos`와 별개)
- **일정 알림**(v23 `notify_enabled`/`notify_offset_minutes`) — 정시/5·10·30분 전 가벼운 알림(알람 아님).
  Native `ScheduleNotificationScheduler.kt`가 예약·부팅 재예약, 수신 시 DB 시각과 정확 비교(#5). 등록/취소는
  `date_schedule_provider.dart` create/update/delete뿐. 탭을 숨기면 예약 전부 취소하고 Native에도 기록(재부팅 후에도 안 뜸)
- 아이콘 미선택 시 내용 텍스트로 자동분류(`MemoCategoryClassifier`: 키워드 하드매핑 → TF-IDF+LogReg → margin 폴백,
  `assets/ml/memo_category_model.json`). 직접 고른 아이콘이 항상 우선. 카테고리 **25종** — 정의 `ml/카테고리_가이드.md`,
  아이콘 `assets/icons/memo_category/README.md`

### 친구 공유
- 공유 코드 `SB2:<익명UID>` / 웹 링크 `https://shiftbell-29f31.web.app` (`lib/web_main.dart` + `web/`, PWA)
- 공유 데이터: 표시 이름·근무 패턴·시작일·근무별 색·날짜별 근무 변경만(메모·OT·알람·수면 제외)
- 로컬 상태 머신 off/active/stop_pending + dirty/generation, 단일 제출 큐, 5초 뒤 pending, 앱 시작·재개 시 재시도(G2)
- 친구 조회는 `Source.server` 강제: 서버가 확인한 notFound/revoked만 캐시 삭제, 오프라인은 캐시 유지 + "확인 불가"
- 공유 상태 7키는 백업 제외(`FriendSyncService.backupExcludedPreferenceKeys`)
- 상세: `docs/release_audit/g2/handoff.md`

### 업데이트 안내
`update_service.dart` — Play In-App Update API 안 씀(전파 지연). Firestore `app_config.latestVersionCode`를 직접 읽음,
포그라운드 복귀마다 재체크(버전코드 dedupe + 쿨다운 6시간). 강제 업데이트는 2026-09-12에 제거.

### 컨디션 매니저 (탭)
`lib/screens/condition_tab.dart` + `lib/services/condition/*` — 교대 일정과 실제 수면을 분석해 **근거 기반** 조언.
원칙과 규칙 표는 아래 **"설계 기록 › 컨디션 매니저"** 참고(새 판정·팁을 넣기 전에 반드시 읽을 것).

### 실제 수면 기록 / 자동 수면 추정
위젯 수동 기록(1순위) + 근무 일정·화면 장기 꺼짐 기반 자동 추정(2순위, 사용자 확인 필요). 규칙은 **"설계 기록 › 수면 기록"** 참고.

### 백업/복구 (2026-09-14 G4로 재작성)
- **내보내기** `backup_service.dart`: 모든 테이블을 한 읽기 트랜잭션에서 `sqlite_master` 자동 스윕 → JSON 파일 하나.
  무엇을 넣고 뺄지는 `backup_policy.dart` 한 곳 — `alarms`는 **미래 custom만**(fixed 파생·snoozed D5 제외),
  친구공유 7키·설치별 설정(백업 상태·권한 요청·업데이트 안내) 제외. **새 원본 테이블/설정은 코드 수정 없이 자동 포함**
  (파생 데이터 테이블만 제외 목록에 추가할 것)
- **자동 백업** `backup_watcher.dart`: 시작·재개·배경 전환 때 내용 지문이 다를 때만, single flight, isolate 인코딩,
  네이티브 백그라운드 I/O, MediaStore `IS_PENDING`으로 완성 후 공개(#18). 복원 중/중단 작업이 있으면 안 씀
- **저장소**: MediaStore `Download/ShiftBell/ShiftBell_Backup[_dev]_YYMMDD.json` — **최신 + 직전 정상본 1개**만 남김(X-07).
  자동 탐지는 최신순 후보를 디코딩·근무표 존재·스키마 검증까지 통과한 첫 파일로 고름. Android 10 미만 미지원. 평문(D9 — 안내로 대응)
- **복원** `restore_coordinator.dart`: 검증(`backup_validator.dart`) → DP 작업 사본 → 네이티브 잠금(`RestoreGate.kt`) →
  옛 OS 예약 취소(`RestoreOs.kt`) → DB 교체(원본 테이블 교체·백업에 없는 원본 테이블은 비움, **이력은 자연키 병합**,
  울림/스누즈 중 알람은 원래 ID로 이월 + 재생 설정 스냅샷, 충돌 시 백업 custom이 새 ID) → 설정 → OS 재조정 → 친구공유 재업로드.
  중단되면 앱 시작 첫 화면 `restore_interrupted_screen.dart`에서 이어서 복원 / 지금 데이터로 계속
- **교차 검토 보강(2026-09-15, X-02~X-09)**: 설정의 덮어쓰기 복원은 루트 네비게이터 전체 화면 `restore_progress_screen.dart`에서
  실행(뒤로가기·탭 이동 불가). 재시작은 `app_restart.dart` — 이 프로세스에서 울리는 알람이 끝난 뒤에만. 이월은 네이티브 울림 상태
  epoch(`RingingAlarmTracker.carryState`)를 DB 교체 트랜잭션 끝에서 다시 비교해 바뀌었으면 롤백 후 재시도, 종료 처리 중 알람·최근
  스누즈도 이월. Guard 재등록도 복원 잠금·DB 재확인 경로. 최종 재조정(엔진·일정 재예약)이 끝까지 못 돌면 미완료로 남김.
  백업에 없는 복원 대상 설정 키는 지워 기본값으로. 설정 자료형 등록표 `kBackupPreferenceTypes`(새 설정 키를 만들면 여기도 추가)
- 신규 설치에서 백업을 자동 탐지 못 하는 기기(삼성 `owner_package_name` NULL 버그)는 온보딩 "이전 백업 불러오기"(SAF)로 직접 선택
- 알려진 한계: 재설치하면 익명 UID가 바뀌어 예전에 공유한 문서를 앱에서 지울 수 없음
- 상세: `docs/release_audit/g4/handoff.md`

---

## 파일 구조 (주요)

```
lib/
├── constants/     alarm_limits · platform_channel · shift_name_limits · ad_config
├── l10n/          app_ko.arb(템플릿) · app_en.arb · l10n_extensions · generated/(커밋 안 함)
├── models/        alarm · shift_schedule · calendar_theme · date_memo · date_schedule · date_overtime
│                  friend_schedule · sleep_record · shift_time_range · backup_payload
├── providers/     alarm · schedule · date_schedule · friend · memo · overtime · work_hours_settings
│                  condition · condition_shift_time · sleep_record · sleep_condition · data_revision · tab_visibility
├── screens/       splash · onboarding · permission_intro · startup_gate · calendar_tab · next_alarm_tab
│                  schedule_management_tab · condition_tab · settings_tab · all_shifts_view · work_hours_settings_screen
│                  friend_* · my_share_code_screen · restore_backup_screen · restore_interrupted_screen · privacy_policy_screen
├── services/      alarm_service · alarm_generation_service · alarm_refresh_service · database_service · db_migration_runner
│                  schedule_notification_service · permission_service · update_service · widget_refresh_service
│                  firebase_bootstrap · friend_share_service · friend_sync_service · memo_category_classifier
│                  backup_* · restore_coordinator · condition/*(분석·판정·예측·점수·수면)
└── web_main.dart  친구공유 웹 뷰어

android/app/src/main/kotlin/com/hwani1103/shiftbell/
├── MainActivity.kt                    MethodChannel 핸들러(백업 파일 I/O·복원 채널 포함)
├── AlarmActivity / AlarmOverlayService / AlarmPlayer / VolumeCalibration / RingingAlarmTracker
├── CustomAlarmReceiver / AlarmActionReceiver / AlarmActionHelper / NotificationHelper
├── AlarmGuardReceiver                 사전 알림 & 자정 하트비트
├── AlarmRefreshEngine ⭐ / AlarmRefreshReceiver / AlarmRefreshUtil / RefreshLockManager
├── AlarmWakeScheduler ⭐              기상 알람 OS 예약·취소·재시도 단일 경로
├── DirectBootReceiver                 부팅·업데이트·정확한 알람 권한 변경
├── DatabaseHelper ⭐ / DbMigrationRunner ⭐
├── ScheduleNotificationScheduler / ScheduleNotificationReceiver
├── SleepDetectionScheduler / SleepDetectionReceiver / SleepScheduleResolver / SleepWidget{Provider,ActionReceiver}
├── RestoreGate / RestoreOs            백업 복원 잠금·OS 단계
└── CalendarWidget{Provider,ScheduleResolver,Holidays}
```

---

## ⚠️ 반드시 지켜야 할 것

### 1. Dart ↔ Kotlin 상수 동기화 (빌드가 강제함)
값이 다르면 `android/app/build.gradle.kts`의 `checkDartKotlinSync`가 빌드를 실패시킴(모든 variant preBuild 의존).

| 값 | Kotlin | Dart |
|----|--------|------|
| DB 스키마 버전 | `DatabaseHelper.kt` `DATABASE_VERSION` (현재 **24**) | `database_service.dart` `version:` |
| DB SQL 원본 목표 버전 | `DatabaseHelper.kt` `DATABASE_VERSION` | `assets/db/migrations.json` `"targetVersion"` |
| 갱신 윈도우 일수 | `AlarmRefreshEngine.kt` `DAYS_AHEAD` (현재 **10**) | `alarm_limits.dart` `kAlarmRefreshWindowDays` |

새로 이런 쌍이 생기면 `checkPair()`를 추가할 것(주석으로 "맞출 것"은 세 번 실패한 방법). hot reload로는 안 걸리니 스키마 변경 후엔 전체 빌드 1회.
빌드 가드가 못 잡는 이중 구현 쌍(손으로 맞춤): 알람 생성 계산(`alarm_generation_service.dart`↔`AlarmRefreshEngine.kt`),
수면 감지 창(`sleep_opportunity.dart`↔`SleepScheduleResolver.kt`), 공휴일(`holiday_util.dart`↔`CalendarWidgetHolidays.kt`).

### 2. 알람 이력은 절대 자동 삭제 금지
`alarm_history` / `alarm_creation_log`는 영구 보존. 정리 로직·마이그레이션·복원에서도 비우지 말 것(복원은 병합).

### 3. Device Protected Storage
Flutter `SharedPreferences`와 Native DP prefs(`alarm_state`, `restore_state`, 수면 감지 상태)는 **서로 다른 경로**. 혼동 금지.
Native 새 키는 `docs/release_audit/contracts.md` §7.2에 등록.

### 4. DB 스키마 변경 절차 (v24~)
**언제**: 앱을 껐다 켜도 남아야 하는 새 데이터일 때만(`CREATE/ALTER TABLE`이 필요할 때). UI·계산·설정값(SharedPreferences)은 해당 없음.

**구조**: 버전별 SQL은 `assets/db/migrations.json` **하나에만** — `migrations`(버전별 증분, 파괴적 SQL 가능) +
`repair`(최신 스키마의 비파괴 최종형, 열 때마다 없는 테이블/컬럼/인덱스만 채움) + `targetVersion`.
Dart `db_migration_runner.dart`와 Native `DbMigrationRunner.kt`가 같은 규칙으로 실행하고, **Native도 첫 DB 접근(업데이트 후 앱
미실행·잠금 해제 전 부팅·알람 수신)에서 직접 마이그레이션**함. 실패하면 던져서 버전 갱신까지 롤백 → 다음 접근 때 재시도.
Native 게이트: 파일 없음·`user_version 0`·디스크>Native면 스킵, 낮으면 마이그레이션, `onCreate`/`onDowngrade`는 예외.
Dart는 실패 시 시작 실패 화면(`startup_gate.dart`) + 다시 시도.

**한 커밋에서 같이 할 것**
1. `migrations.json` — `migrations` 끝에 `{"version": N, "sql": [...]}`, `repair` 최종형 반영(새 테이블은 `CREATE TABLE IF NOT EXISTS` 최종형,
   새 컬럼은 그 CREATE 최종형 수정 + `ALTER TABLE ... ADD COLUMN` 항목), `"targetVersion": N`
2. `database_service.dart` — `version:` N, `_onCreate()`에 같은 최종형(`IF NOT EXISTS`)
3. `DatabaseHelper.kt` — `DATABASE_VERSION` N (+ Native가 읽는 코드)
4. 이 문서의 DB 스키마 절

**규칙**: 기존 `migrations` 항목 수정·삭제 금지(스토어 v12·v14·v15·v17·v18 사용자가 전 구간 통과) · `_onCreate`/`migrations`/`repair`
세 곳 모두(하나만 고치면 기존 사용자 쪽이 조용히 깨짐) · ALTER를 try/catch로 삼키지 말 것 · 한 항목에 SQL 한 문장(`;` 금지) ·
`NOT NULL` 추가 시 `DEFAULT` 필수 · 컬럼 삭제/이름 변경 금지 · Dart 로직이 필요한 데이터 변환은 이 구조로 불가(별도 설계) ·
repair는 `CREATE TABLE IF NOT EXISTS`/`CREATE [UNIQUE] INDEX IF NOT EXISTS`/`ALTER TABLE ADD COLUMN`만.

**검증**: `flutter analyze` → `cd android && ./gradlew :app:checkDartKotlinSync` → `./gradlew :app:testDevDebugUnitTest`
(G0 fixture: 스토어 버전들에서 올린 결과 == 신규 생성 DB) → 기기에서 **기존 데이터 있는 dev 앱 위에 덮어 설치**(신규 설치는 업그레이드를
못 잡음) → 앱 안 열고 재부팅/알람 수신 후 `adb logcat -s DatabaseHelper DbMigrationRunner`에서 `✅ Native 마이그레이션 완료`.

**증상**: 앱은 멀쩡한데 위젯이 "스케줄을 먼저 설정", 알람 화면 시각 빈칸, 고정 알람 수정이 반영 안 됨, 10일치가 안 늘어남 →
logcat `DatabaseHelper`/`DbMigrationRunner`의 `❌` 또는 `디스크 DB(vN)가 Native(vM)보다 높음`부터 확인.
**다운그레이드**: 낮은 버전 앱을 덮어 설치하면 Dart 시작 실패·Native 스킵(개발 중 구버전 APK 수동 설치 주의).

### 5. 알람 갱신 트리거 지점
알람 수신(`CustomAlarmReceiver`) · 자정/알람 20분 전(`AlarmGuardReceiver`) · 알람 끄기·스누즈 · 앱 실행/재개(`MainActivity`) ·
부팅/업데이트/정확한 알람 권한 허용(`DirectBootReceiver`). 백업 복원 중에는 모두 미루고 복원 작업이 끝에서 직접 재조정.

### 6. 알람 테스트
알람 테스트 중 설정 → 앱 → **강제 중지 금지**(OS가 예약 알람을 전부 지움). 최근 앱에서 스와이프 종료는 괜찮음.

---

## DB 스키마 (v24)

`shift_schedule` · `shift_alarm_templates` · `alarms` · `alarm_types` · `alarm_history`(영구) · `alarm_creation_log`(영구) ·
`alarm_overrides` · `date_memos` · `date_schedules` · `date_overtime` · `friends` · `condition_shift_times` · `sleep_records` ·
`sleep_expected_bedtime`(입력 기능 삭제, 빈 테이블로 스키마만 유지)

- v16 `friends` 추가 · v17 Firestore `ownerId` 기반 재설계 · v18 `shift_schedule.custom_shift_colors`
- v19 템플릿/알람/이력/생성로그에 `day_offset`
- v20 `date_schedules`(+`predicted_category`/`is_user_corrected` — 자동분류 재학습용 수정 로그)
- v21 `condition_shift_times`(근무명별 출퇴근 분) · v22 `sleep_records`/`sleep_expected_bedtime`(Native가 직접 읽고 씀)
- v23 `date_schedules.notify_enabled`/`notify_offset_minutes`(Native 재예약용으로 읽음)
- v24 `alarm_overrides`(`slot_time` `yyyy-MM-dd'T'HH:mm:ss` Locale.US 초 00, `shift_type`, `day_offset`, `action` skip/set_type,
  `alarm_type_id`, `origin_date`, `origin_shift`, UNIQUE(slot_time, shift_type, day_offset)) + 마이그레이션 구조 교체(위 ⚠️4)

---

## 설계 기록 (옛 문서 요약 — 다시 논의하지 말 것 / 바꾸기 전에 읽을 것)

### 컨디션 매니저
- **원칙**: 판정은 이름 붙은 Rule + Evidence ID로만. **근거 없는 판정 금지** — 새 규칙·팁은 먼저 근거를 조사해
  `evidence_database.dart`에 `source`/URL과 함께 넣은 뒤 사용. 질병 위험(IARC 등)은 영구 제외. "추정", "~로 보고됩니다" 표현, 단정 금지
- **숫자 점수 예외**: 원래 "점수·% 금지"였으나 사용자 요청으로 `condition_score.dart`(0~100, 탭의 "컨디션 점수 N점")**만** 승인된 예외.
  다른 화면에 점수·%·진단을 추가하는 선례로 쓰지 말 것. 3단계 판정(NORMAL/ATTENTION/HIGH_LOAD)은 그대로
- **Evidence 13개**: 001 교대 방향(NIOSH M5) · 002/003 근무 사이 11시간(NIOSH·EU 2003/88/EC 제3조) · 004 12시간 근무 사고위험(Folkard & Lombardi 2006) ·
  005 연속 장시간 후 휴식(NIOSH) · 006 야간 후 수면 우선 · 007 야간 전 낮잠(AASM 2025, 근거 매우 낮음 — 팁만) · 008 카페인 취침 6시간 전(Drake 2013) ·
  009 귀가길 빛 관리(+졸음운전 경고 필수) · 010 야간 중 식사 · 011 성인 수면 7~9시간(NSF 2015) · 012 주 48시간(EU 제6조) ·
  013 연속 야간근무 횟수(Folkard & Tucker 2003, 2차 인용으로만 확인). 운동 시점·불규칙 근무 정량화는 근거 없음 → 판정 금지
- **판정(`condition_rule_engine.dart` v2)**: ATTENTION 신호 5개 — 회복<11h(002/003), 근무≥12h(004), 최근 7일 OT≥8h(012), 역방향 교대(001),
  연속 야간≥3일(013). 2개 이상 겹치면 HIGH_LOAD("겹치면 심각"은 앱 설계 판단임을 문구에 명시). 단독 HIGH_LOAD: 12h 근무 3일 연속+회복<48h(004/005),
  연속 야간≥4일(013). 연속 근무일수 자체는 근거가 없어 설명(context)에만. `evaluate(otMinutesByDate:)` 기본값 빈 맵이면 OT 규칙 꺼짐
- **점수**: 100에서 요인별 감점(`_w*` 상수, 사용자가 조정할 1차 설계값), 문제 축 합계 상한 47, 교대근무 기본 부담은 상한 밖.
  측정 안 된 수면은 감점 안 함. 수면 기준은 7시간(EVIDENCE-011)
- **오늘의 컨디션(`today_forecast_engine.dart`)**: ML 아님, 조합형 규칙(축별 상태 × 문구 변주 × 날짜 시드 로테이션).
  헤드라인 우선순위 = 어제 급성 이벤트(수면<6h 등) > 최근 5일 실측 피로(`_classifyRecentFatigue`, 오늘까지만 — **미래 근무 변경은 안 봄**) > 8주 OT 추세.
  원자료 나열("3일 야간") 대신 정성 표현, 추가 언급 최대 1개. 개인 평소 근무시간 비교는 문구에만(12시간 절대 기준 규칙은 그대로)
- **팁 카드**: "교대근무 건강 & 수면관리 Tip" — Firestore `health_tips`(없으면 로컬 15개), 하루 1개 날짜 나머지 연산 로테이션
- **출퇴근 시각 입력**은 설정 → 근무시간 및 OT 설정. 한 근무라도 입력돼 있으면 탭 동작. 이 탭 문구는 한국어 하드코딩(1차, l10n 미적용)
- 남은 과제: 실데이터로 임계값 튜닝, EVIDENCE-013 1차 원문 확인, "12시간 근무자는 휴일이 더 잦다" 보완은 미반영
- 테스트: `test/condition_rule_engine_v2_test.dart`, `today_forecast_engine*_test.dart`, `condition_score_test.dart`, `sleep_history_test.dart`

### 수면 기록 / 자동 추정
- **감지 방식 결정**: `AlarmManager` 20분 샘플링만 사용. 화면 on/off 상시 리시버·Foreground Service는 기각, `UsageStatsManager`(특수 권한·잠금 시 null)는
  보류, Activity Recognition 센서는 **사용자가 "현재 방식 유지"로 결정 — 다시 꺼내지 말 것**
- **감지 창(메인 잠 전용)**: 야간 근무(시작 17:00~04:59)는 종료 1시간 전부터, 그 외·휴무는 21시 이후부터, 둘 다 최대 9시간(다음 근무가 더 이르면 컷).
  근무 중 낮잠은 자동 감지 안 함(위젯 수동 전용). 활성 창이 예정 창보다 우선. 같은 창에 이미 시작한 기록이 있으면 새 후보 안 만듦
- **판정**: 창 안에서 화면 꺼짐 2회 연속이면 후보(시작은 첫 꺼짐 샘플로 소급), 켜짐이면 종료(확정 아님, 확인 카드). 2시간 미만 자동 후보는 폐기,
  수동은 2분 미만 폐기. 앱 재개·Guard·부팅에서 `SleepDetectionReceiver.checkNow()`로 즉시 판정. 확인 카드에서 2회 이상 거부한 시간대는 스킵(거부 학습)
- **위젯**: "오늘 근무 / 상태" + 수면·기상 버튼. AUTO 진행 중 "수면"은 무시(소급 시각 보호), "기상"은 그 자리에서 확정. 기상 후 수면시간 요약은 표시 안 함
- **분류는 저장하지 않음**: 주 수면/낮잠은 조회 때 길이(4시간)로 계산, 야간 근무 종료 후 16시간 안에 시작한 수면은 근무 당일로 귀속,
  한 밤의 수면시간은 매칭되는 낮잠+메인 합계
- **완전 분리**: 감지는 `sleep_records`에만 쓰고 `ConditionRuleEngine`은 수면을 모름(보조 문구는 `sleep_condition_extras.dart`)

### 알람 / 일정 / UI 결정
- 알람은 Native 경로로만 신뢰(`flutter_local_notifications` 같은 순수 Dart 예약은 Doze·OEM 신뢰성 때문에 기각), 일정 알림도 같은 인프라
- `B1/B2`(알람 재생이 `onReceive` 동기 `prepare()`, UI 표시 500ms 지연)는 실기기 근거 없이 안 건드리기로 함
- 일정관리 탭 좌표 상수는 `(N * 7 / 8).h/.w/.r` 규칙(기준 기기 SM S948N), `.sp`에는 적용 안 함. 일정 생성은 우측 하단 FAB + 스크롤 추적
  (끝단 오버슛·calibration은 피커 활성 때만). 시트는 `showGeneralDialog` 고정 하단 시트(키보드와 무관)
- 좌우 스와이프: 달력=월 이동, 일정관리=이전/다음 날, 다음알람·설정=없음
- **홈 위젯 테마 반영은 철회**(2026-08-13): 9테마 구현까지 했다가 사용자 결정으로 라이트 고정으로 되돌림 — 요청 전까지 손대지 말 것
- 영어화 결정: 근무명 최대 10자(ellipsis), 요일은 일요일 시작, 공휴일은 한국어에서만, AM/PM은 `commonAm/Pm` 별도 키,
  내부 센티널 `'미설정'`은 번역 안 함, 휴무 판정 `isRestShiftName()`(Off/Rest/Holiday 포함)
- 메모에 시각을 붙이는 확장(`date_memos` 시간 컬럼)은 미착수·미결정(자정 넘김 저장 방식, 하루 3개 표시 한계가 쟁점) — 일정은 `date_schedules`로 따로 구현됨

### 카테고리 자동분류 (ml/)
- 파이프라인: 키워드 하드매핑(`ml/keyword_router.py` ↔ `memo_category_classifier.dart` 동일) → char 2~3gram TF-IDF + LogReg → margin 0.08 미만이면 기타
- 재학습 절차: 데이터 수정 → `ml/check_keyword_regressions.py`(하드매핑 순증 충돌 0 확인) → `ml/train.py` → `ml/export.py` →
  `ml/verify_export.py`(Dart용 JSON 재현 오차 확인) → Dart 테스트 `test/memo_category_classifier_test.dart`
- 교훈: "명확해 보이는" 키워드도 실측 없이 하드매핑하지 말 것(수영/헬스는 오히려 정확도 하락), 형/누나/언니/오빠/동생은 호칭이라 하드매핑 제외,
  "요가"는 "필요가" 오탐 때문에 어절 시작만, 구매·수리 동사가 있으면 활동 카테고리 보류
- 보류: Phase 6(근무 스케줄 피처), Phase 7(실사용 수정 로그 재학습 — 동의 UX 필요), 임베딩 모델(용량 20~90MB 증가라 근거 확실할 때만)

### 친구공유 / 웹 뷰어
- 문서 ID = 익명 UID라 read 키(코드)와 write 키(uid)가 분리됨. 코드 형식 `SB1:`(옛 스냅샷)은 더 이상 디코딩 안 함
- 웹 뷰어 PWA 재실행은 standalone 모드일 때만 마지막 ownerId로 폴백(공유 브라우저 노출 방지)
- **claude-in-chrome 자동화 환경에서만 웹 뷰어 Firebase 초기화가 실패**한 전례 — 브라우저 자동화로 JS 초기화 실패가 보이면 실기기 브라우저로 먼저 확인
- 알려진 한계: 재설치 시 옛 UID 문서가 서버에 남음(앱에서 회수 불가), 서버 rules에 형식·크기·회차 강제 없음(D7)

### 백업 (G4 이전 조사에서 남길 교훈)
- `android:allowBackup="false"`, DP 저장소는 Auto Backup 대상 아님 → 자체 MediaStore 파일 방식 채택(로그인·클라우드 없음)
- 삼성 등 OEM에서 MediaStore selection/LIKE 쿼리가 결과를 못 찾거나 `owner_package_name`이 NULL — selection 없는 전체 조회 + 이름 필터,
  행 URI 단위 삭제, 실패 대비 SAF 수동 선택을 항상 제공
- dev/prod 백업 파일명 분리(`ShiftBell_Backup_dev_`), 파일명에 패키지명 노출 금지

### 옛 점검 리포트(08-14, 09-01, 09-04)에서 아직 남은 것
- (Low) `ShiftTimeRange` 출퇴근을 같은 시각으로 입력하면 24시간으로 계산됨
- (Low, debug 전용) 달력 메모 바텀시트에서 포커스 상태로 뒤로가기 시 `_dependents.isEmpty` assertion — `WillPopScope`→`PopScope` 리팩터 필요, release 영향 없음
- (정보) `RefreshLockManager` TTL 30초가 실제 완료를 확인 안 함, 전체근무표 조별 테이블 좁은 화면 overflow 방어 없음, 기준일 `DateTime(2024,1,1)` 두 파일 중복
- 나머지 HIGH/MEDIUM(컨디션 무한루프, 트랜잭션 중 OS 호출, 자동백업 감지, rename 시 컨디션 시각 고아, 복원 오보고, 00:00 음수 시각, 볼륨 무음 등)은 전부 수정됨

---

## 알려진 상태 / 문서 위치

- `flutter analyze` — error는 `lib/web_main.dart`의 `dart:js_util` 1건(웹 전용), warning은 기존 미사용 import 등
- 자동 테스트: `flutter test`(Dart, `test/release_audit/g0~g2` 포함), `cd android && sh ./gradlew testDevDebugUnitTest`(Kotlin JUnit4+Robolectric,
  `robolectric.properties`로 SDK 34 고정). `integration_test/`는 호스트 RAM 6GB 한계로 2026-09-13에 제거함. 빌드·테스트는 한 번에 하나, 전에 `gradlew --stop`
- 저장소 히스토리에 예전 logcat 덤프 86MB(팩 16MB)가 남아 있음(추적 해제됨)
- 출시전 감사: 기준 `출시전_코드감사_2026-09-13.md`(원본 39건) + `출시전_코드감사_검토결과_v4_2026-09-13.md`(수정 #1~#31) +
  실행계획 `출시전_수정작업_그룹별_실행계획_및_세션인계_2026-09-14.md` + 진행 기록 `docs/release_audit/`(작업판 `task_board.md`, 그룹별 handoff,
  AI 위임 결정 `decisions_delegated_2026-09-14.md`, 실기기·Console 테스트 `g6/device_test_plan.md`)
- 미검증: 홈 위젯 실기기 표시, G4 백업·복원 실제 실행, G5 prod release 광고·Analytics 목적지
