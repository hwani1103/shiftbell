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
  - `friend_schedules` 친구 근무표(익명 UID 문서) / `app_config` 업데이트 안내(읽기 전용) / `health_tips`(규칙에 읽기 허용은 남아 있지만 2026-09-15 범용 Tip 삭제 후 앱은 읽지 않음)
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

### 수면·회복 탭 (구 컨디션 매니저, 2026-09-15 범위 축소)
`lib/screens/condition_tab.dart` + `lib/services/condition/*` — 하단 탭 이름은 "수면·회복"(클래스·provider·저장 키 `condition_tab_enabled`는 호환 위해 그대로).
남은 기능: **오늘의 컨디션**(`recovery_briefing_engine.dart` — 지금 시각 기준 확인된 사실 / 시각이 박힌 추천 행동 최대 3개 / 판단 범위) +
자동 기록 확인 카드 + 최근 수면 기록 미니 달력(근무시간 입력 전에도 기록 가능). **컨디션 점수·범용 건강 Tip·날짜 시드 문구 엔진은 삭제**.
원칙과 규칙 표는 아래 **"설계 기록 › 컨디션 매니저"** 참고(새 판정·행동을 넣기 전에 반드시 읽을 것).

### 실제 수면 기록 / 자동 수면 추정
위젯 수동 기록(1순위) + 근무 일정·화면 장기 꺼짐 기반 자동 추정(2순위, 사용자 확인 필요). 규칙은 **"설계 기록 › 수면 기록"** 참고.

### 백업/복구 (2026-09-14 G4로 재작성)
- **내보내기** `backup_service.dart`: 모든 테이블을 한 읽기 트랜잭션에서 `sqlite_master` 자동 스윕 → JSON 파일 하나.
  무엇을 넣고 뺄지는 `backup_policy.dart` 한 곳 — `alarms`는 **미래 custom만**(fixed 파생·snoozed D5 제외),
  친구공유 7키·설치별 설정(백업 상태·권한 요청·업데이트 안내) 제외. **새 원본 테이블/설정은 코드 수정 없이 자동 포함**
  (파생 데이터 테이블만 제외 목록에 추가할 것)
- **자동 백업** `backup_watcher.dart`: 시작·재개·배경 전환 때 내용 지문이 다를 때만, single flight, isolate 인코딩,
  네이티브 백그라운드 I/O, MediaStore `IS_PENDING`으로 완성 후 공개(#18). 복원 중/중단 작업이 있으면 안 씀
- **저장소**: MediaStore `Download/ShiftBell/ShiftBell_Backup[_dev]_YYMMDD_HHmm.json`(2026-09-17 시각 추가 — 아래 “설계 기록 › 백업” 참고) — **최신 + 직전 정상본 1개**만 남김(X-07).
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
- **앱을 지우고 다시 깔 뒤에는 이전 백업을 자동 탐지할 수 없음(버그 아니라 사양)** — 온보딩 "이전 백업 불러오기"(SAF)로 직접 선택하는 것이 유일한 경로
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
- **점수 삭제(2026-09-15)**: 유일한 예외였던 `condition_score.dart`(0~100)를 출시 적합성 재검토 후 삭제 — 근거보다 임의 가중치 영향이 컸고
  수면 기록이 없으면 감점해 "상태 나쁨"과 "데이터 없음"이 섞였음. 이제 **점수·%·진단은 어디에도 없음**(다시 만들지 말 것).
  3단계 판정(NORMAL/ATTENTION/HIGH_LOAD)은 그대로 — 카드 우측 칩("근무 부담 보통/주의가 필요한 날/회복 부담이 큰 날")으로만 표시
- **Evidence 14개**: 001 교대 방향(NIOSH M5) · 002/003 근무 사이 11시간(NIOSH·EU 2003/88/EC 제3조) · 004 12시간 근무 사고위험(Folkard & Lombardi 2006) ·
  005 근무시간대별 연속근무 후 휴식(NIOSH M5 — 2026-09-17 재조사로 8h/10h/12h 구간별 수치로 일반화, 원문에 "며칠 몰아 일하고 몰아 쉬는 패턴을 피하라"는
  일반 원칙도 포함) · 006 야간 후 수면 우선 · 007 야간 전 낮잠(AASM 2025, 근거 매우 낮음 — 팁만) · 008 카페인 취침 6시간 전(Drake 2013) ·
  009 귀가길 빛 관리(+졸음운전 경고 필수) · 010 야간 중 식사 · 011 성인 수면 7~9시간(NSF 2015) · 012 주 48시간(EU 제6조) ·
  013 연속 야간근무 횟수(Folkard & Tucker 2003, 2차 인용으로만 확인) · **014(2026-09-17 신규)** 주 60시간 상한(IOM 2004 Keeping Patients Safe) +
  참고용 주 40시간(2014 체계적 검토, 둘 다 NIOSH M5에 인용된 수치). 운동 시점·불규칙 근무 정량화는 근거 없음 → 판정 금지
- **판정 v3 재설계(2026-09-17, `condition_rule_engine.dart`)** — 계기: 사용자 지적 "12시간이 표준 근무인 사람에게 매 근무일 캐션이 뜨는 건
  실행 불가능한 정보이자 경고 피로만 유발한다"와 "하루 근무시간보다 최근 며칠간 총량·직전 휴식 여부로 판단해야 한다"·"근무시간과 무관하게 연속근무일수
  자체도 힘들 수 있다"(예: 12h×15일/월과 8h×22일/월은 총량이 비슷 — 표준 근무시간이 다르다는 이유만으로 다르게 평가하면 안 됨). 이에 따라
  **"절대 12시간 임계값 단독 트리거"(RULE_LONG_SHIFT)를 완전히 폐지**하고 다음으로 대체:
  - `RULE_EXTENDED_STREAK_SHORT_BREAK`: 오늘/직전 근무의 실제 근무시간에 맞는 버킷(`ConditionRuleEngine.streakBucketFor`) — 8시간대→5일
    연속+회복<24h, 10시간대→4일 연속+회복<24h, 12시간대→3일 연속+회복<48h(004/005) — 이면 단독 HIGH_LOAD. 8시간 미만은 이 근거가 안 다뤄 버킷 없음(레벨 불관여)
  - `RULE_WEEKLY_TOTAL_LOAD`: 최근 7일 **총 실근무시간(기본근무+초과근무, OT만이 아님)**이 48시간 이상이면 ATTENTION(012), 60시간 이상이면
    그 자체로 단독 HIGH_LOAD(014) — "12h×15일/월 vs 8h×22일/월"처럼 하루 근무시간이 달라도 총량이 비슷하면 비슷하게 평가되는 핵심 장치
  - `RULE_CONSECUTIVE_WORKDAYS`(신규): 근무시간과 무관하게 쉬는 날 없이 이어지는 연속근무일수 자체 — 7일 이상 ATTENTION, 10일 이상 단독
    HIGH_LOAD. 정확한 근거 수치가 없어(005의 일반 원칙만 차용) **"이 앱의 판단"임을 문구에 항상 명시**(RULE_COMPOUND_HIGH_LOAD와 동일 취급)
  - 유지: 회복<11h(002/003) · 역방향 교대(001) · 연속 야간≥3일 ATTENTION/≥4일 단독 HIGH_LOAD(013)
  - ATTENTION급 신호(회복부족/주간총량/역방향/연속야간/연속근무일수) 2개 이상 겹치면 HIGH_LOAD("겹치면 심각"은 앱 설계 판단, 문구에 명시)는 그대로
  - 직전 충분한 휴식(예: 5일 연속 휴무 뒤 12시간 근무 하루)은 스트릭·회복시간이 자연히 리셋되므로 **별도의 "휴식 크레딧" 계산 없이도** 캐션이 안 뜸
    (연속 스트릭/회복시간 계산 자체가 이미 "직전에 쉬었는지"를 반영하는 구조라 중복 구현하지 않음 — 설계 검토 완료)
  - `evaluate(otMinutesByDate:)` 기본값 빈 맵이면 총 근무시간 계산에서 OT 부분만 0으로 취급(기본근무는 analyzer로 항상 계산되므로 이전처럼
    "신호 자체가 꺼짐"이 아님 — 이 부분이 v2와 다른 점)
- **브리핑 문구 품질 재검토(2026-09-18)** — 계기: v3 신호를 실제 시나리오로 여러 개 돌려서 문장을 직접 읽어본 결과 발견한 문제 2가지.
  1. **안전 상한(캡) 노출 버그**: `ShiftPatternAnalyzer`의 연속일수 계산 3종(`consecutiveNightStreakEndingAt`/`consecutiveWorkStreakEndingAt`/
     `consecutiveLongShiftStreakEndingAt`)이 무한루프 방지용 `maxLookbackDays`(기본 180)에 도달하면 그 숫자를 그대로 "180일 연속 근무"처럼
     문구에 노출하던 문제. 반환 타입을 `int`에서 `ConsecutiveStreak`(`({int days, bool capped})`) 레코드로 바꿔 캡 도달 여부를 타입 차원에서
     드러내고, `ConditionRuleEngine.streakClause(streak, normal:, capped:)` 하나를 두 파일(`condition_rule_engine.dart`/
     `recovery_briefing_engine.dart`)의 연속일수 문구 생성 지점 전부가 거치게 함 - 캡에 도달하면 숫자 대신 "휴무 없이 매우 오래 이어지고
     있어요" 같은 완결된 문장으로 통째로 바뀜(숫자만 치환하면 문법이 깨져서 항상 문장 전체를 따로 받음).
  2. **같은 정보의 중복 노출**: `RULE_EXTENDED_STREAK_SHORT_BREAK`(근무시간대별 버킷)와 `RULE_CONSECUTIVE_WORKDAYS`(근무시간 무관)가 같은 날
     함께 fire하면 "쉬지 않고 일했다"를 두 문장으로 반복했음. `recovery_briefing_engine.dart`에서 두 신호를 한 곳(topic:
     `BriefingTopic.longWorkStreak`)에서 함께 계산해 fact/action을 최대 1개만 생성하도록 통합 - 버킷이 fire하면 그걸 우선하고, 전체
     연속근무일수가 버킷 연속일수보다 더 길면(짧은 근무를 섞어가며 계속 일한 경우) "12시간 이상 근무 3일 연속(전체 연속근무는 8일째)"처럼
     괄호로 병기해 정보 손실 없이 한 문장으로 합침. `BriefingFact`/`BriefingAction`에 `topic`(`BriefingTopic` - sleepAmount/sleepAverage/
     recoveryGap/nightStreak/longWorkStreak/weeklyLoad/direction/other) 필드를 추가하고, `buildRecoveryBriefing()` 반환 직전에
     `_dedupByTopic()`로 같은 topic이 여러 개면 먼저 만들어진(=더 근거가 강한) 것만 남기는 안전망을 범용으로 둠.
  3. **휴무 첫날 정보 공백 발견 및 수정**: 연속근무일수 관련 fact/action이 `if (ctx != null)`로 막혀 있어서, 휴무 첫날(ctx가 null인 phase)엔
     "어제까지 힘들게 일했다"는 정보가 통째로 안 뜨던 공백을 발견 - 위 longWorkStreak 통합 블록에서 `ctx ?? last`로 폴백해서 고침(같은
     파일의 버킷 로직이 이미 쓰던 패턴). `RULE_CONSECUTIVE_WORKDAYS`는 엔진이 "오늘"이 휴무면 항상 0으로 리셋하므로(오늘 자체의 레벨
     판정용 설계라 맞는 동작), `base.levelFindings`로 확인하는 대신 `streakInst.date`로 직접 재계산함.
  4. **회귀 테스트 상설화**: `test/recovery_briefing_overlap_scenarios_test.dart` 신설 - 위 시나리오들(겹침·캡 경계·휴무 첫날 폴백·총량
     동등성·역방향 겹침 등 8개)을 실제 assert(topic 중복 없음, "180일" 리터럴 없음, 특정 문구 포함)로 고정. 앞으로 신호를 추가/수정할 때 이
     파일을 먼저 돌려서 실제 렌더링 문장이 여전히 자연스러운지 확인할 것.
- **오늘의 컨디션(`recovery_briefing_engine.dart`, 2026-09-15 최초 도입 — `today_forecast_engine.dart` 대체, 2026-09-17 v3 신호 반영,
  2026-09-18 문구 품질 재검토 반영)**: 순수 함수,
  `now` 주입. 위치 판정(근무 중 / 출근 3시간 이내 / 퇴근 후 16시간 이내 / 오늘 근무 대기 / 휴무 / 불명) → **확인된 사실**(이번 근무 전·퇴근 후 실제 수면,
  근무 사이 회복시간 <11h 경고, 연속 야간, **장기연속근무(topic: longWorkStreak - 근무시간대별 버킷과 근무시간 무관 연속근무일수를 하나로
  통합, 위 문구 품질 재검토 참고)**, 최근 7일 총 실근무시간(48h/60h 2단계), 역방향 전환,
  최근 7일 평균 수면 — 기록한 날 3일 이상일 때만). **"오늘 근무가 N시간이라 캐션"이라는 절대 임계값 문구는
  더 이상 없음** — 근무시간/근무명은 situation 줄에서 중립적으로만 보여줌
  → **추천 행동** 최대 3개, 우선순위 안전(퇴근길 빛·운전) > 수면(늦어도 몇 시에 잠자리/지금 자도 최대 N시간) > 야간 전 낮잠 > 카페인 끊을 시각 > 야간 식사 >
  연속근무 완화 > 누적 부담 > 기록 안내
  → **판단 범위**(2주 수면 기록 없음·평균 계산 불가·출퇴근 시각 미입력 근무명·확인 전 자동 기록 N건). 수면 기록이 없다고 상태를 깎지 않음.
  기준값은 `ConditionRuleEngine` 상수(public, `streakBucketFor`/`streakClause` 포함)를 그대로 씀. 60분 준비 여유·3h/16h 구간은 연구값 아닌
  화면 관례값. 시각 없는 근무가 끼면 직전/다음 근무를 단정 안 함. 건강 기준·조언은 근거 ID 필수(기록 안내 `record_sleep`만 예외, 테스트가
  강제). facts/actions는 `BriefingTopic` 기준으로 dedup됨(위 문구 품질 재검토 참고). 화면은 1분 시계
  (`briefingClockProvider`, autoDispose)로 남은 시간 갱신, "근거 보기"로 출처 표시
- **범용 건강 Tip 삭제(2026-09-15)**: 개인화되지 않는 날짜 로테이션 팁이라 제거(`health_tip_provider`·`health_tips_catalog`·`HealthTip` 삭제, Firestore 규칙은 그대로)
- **출퇴근 시각 입력**은 설정 → 근무시간 및 OT 설정. 한 근무라도 입력돼 있으면 오늘의 컨디션 표시(없으면 설정 안내 카드 + "근무시간 입력하기" 버튼, 수면 기록은 가능).
  이 탭 문구는 한국어 하드코딩(1차, l10n 미적용 — 영어 로케일에선 탭 자체가 안 보임)
- 남은 과제: 실데이터로 임계값 튜닝(특히 신규 RULE_CONSECUTIVE_WORKDAYS의 7일/10일), EVIDENCE-013/014 1차 원문 확인(둘 다 2차 인용만 확인),
  "12시간 근무자는 휴일이 더 잦다" 보완은 미반영, 완전히 규칙적인 스케줄+수면습관에서 브리핑 문구가 며칠 단위로 수렴하는 문제는 v3~문구 품질
  재검토로 상당히 완화됐으나 완전 해결은 아님(누적 수치 자체가 매일 미세하게 달라지므로 자연 완화). `ConsecutiveStreak.capped`는 "정확히
  캡 값(180)과 같으면 캡으로 취급"하는 보수적 근사라, 실제 연속일수가 우연히 180과 정확히 같고 다음날 끊기는 극히 드문 경우엔 "휴무 없이
  매우 오래"로 약간 과장되게 표시될 수 있음(정확한 숫자 오표시보다 안전한 쪽 트레이드오프로 의도한 것)
- 테스트: `test/condition_rule_engine_v2_test.dart`(2026-09-17 v3 신호 포함 — 총량 동등성, 휴식 후 장시간근무 vs 무휴식 장기연속근무, 문구
  다양성 케이스 추가), `test/recovery_briefing_engine_test.dart`(위치별 사실·행동·판단 범위, 근거 규칙, Q-07 손상 행),
  `test/recovery_briefing_overlap_scenarios_test.dart`(2026-09-18 신설 - 겹침 시나리오의 topic 중복·캡 노출 회귀), `sleep_history_test.dart`

### 수면 기록 / 자동 추정
- **감지 방식 결정**: `AlarmManager` 20분 샘플링만 사용. 화면 on/off 상시 리시버·Foreground Service는 기각, `UsageStatsManager`(특수 권한·잠금 시 null)는
  보류, Activity Recognition 센서는 **사용자가 "현재 방식 유지"로 결정 — 다시 꺼내지 말 것**
- **감지 창(메인 잠 전용)**: 야간 근무(시작 17:00~04:59)는 종료 1시간 전부터, 그 외·휴무는 21시 이후부터, 둘 다 최대 9시간(다음 근무가 더 이르면 컷).
  근무 중 낮잠은 자동 감지 안 함(위젯 수동 전용). 활성 창이 예정 창보다 우선. 같은 창에 이미 시작한 기록이 있으면 새 후보 안 만듦
- **판정**: 창 안에서 화면 꺼짐 2회 연속이면 후보(시작은 첫 꺼짐 샘플로 소급), 켜짐이면 종료(확정 아님, 확인 카드). 2시간 미만 자동 후보는 폐기,
  수동은 2분 미만 폐기. 앱 재개·Guard·부팅에서 `SleepDetectionReceiver.checkNow()`로 즉시 판정. 확인 카드에서 2회 이상 거부한 시간대는 스킵(거부 학습)
- **위젯**: "오늘 근무 / 상태" + 수면·기상 버튼. AUTO 진행 중 "수면"은 무시(소급 시각 보호), "기상"은 그 자리에서 확정. 기상 후 수면시간 요약은 표시 안 함
- **분류는 저장하지 않음**: 주 수면/낮잠은 조회 때 계산(2시간 이상이면 주 수면 후보, 근무와 겹치거나 오늘 야간 출근 전에 끝난 잠은 낮잠,
  후보가 여럿이면 가장 긴 것 - `sleep_day_slots.dart`). 어제 야간 퇴근 뒤 **오늘 21시 전**에 시작한 수면은 야간 근무일로 귀속(2026-09-06 재설계,
  예전 "퇴근 후 16시간" 문구는 낡은 것). 한 밤의 수면시간은 매칭되는 낮잠+메인 합계. 수면·회복 탭 확인 카드는 최신 3건만 표시(2026-09-15)
- **완전 분리**: 감지는 `sleep_records`에만 쓰고 `ConditionRuleEngine`은 수면을 모름(수면은 `recovery_briefing_engine.dart`의 사실·행동에만 쓰임)
- **손상 행 방어(2026-09-15, Q-07)**: `decodeSleepRecordRows` — 날짜가 깨진 행 하나 때문에 수면 목록 전체가 안 뜨던 문제, 깨진 행만 건너뛰고 로그(행은 지우지 않음)
- **확인 카드 문구**: "이때 주무셨나요?" + "확인한 기록만 오늘의 컨디션에 반영, 아니면 기록하지 않기(다음부터 덜 잡힘)" — 확인을 미루면 분석에서 빠진다는 걸 알림(자동 확정은 여전히 금지)

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
- ⚠️ **2026-09-17 정정** — 그동안 "삼성 OEM 버그(`owner_package_name` NULL)"로 적어 둔 현상의 진짜 원인은 **앱을 삭제하면
  MediaStore가 그 앱이 만든 행의 소유자를 비우기 때문**(파일은 남음). 이 앱은 저장소 권한이 없고 targetSdk 36 → 자기가 소유한 행만 보임.
  그래서 예전 설치본이 남긴 백업은 조회도 삭제도 안 되고, 같은 이름으로 다시 쓰면 MediaStore가 `… (1).json`을 만들어 **파일이 쌓임**
  (2026-09-17 실측: 12개 중 10개가 소유자 NULL, 재설치 시각 이전 파일과 정확히 일치. 설치본당 최신+직전 2개 유지는 정상 동작). 대응:
  파일명에 시각까지 넣어 `(1)` 중복을 없애고(2026-09-17), 수동 선택 안내에서 "가장 최근 것을 고르고 다음 화면에서 저장 시각 확인"을 안내.
  **이걸 고치겠다고 저장소 권한(READ_MEDIA/MANAGE_EXTERNAL_STORAGE)을 받지 말 것.** 옆 앱(dev↔prod) 백업을 서로 읽거나 지우는 사고도
  구조상 불가능(서로의 행이 안 보임) — 접두어 분리는 "손으로 고를 때 구분"의 의미만 있음. selection 없는 전체 조회 + 이름 필터,
  행 URI 단위 삭제, SAF 수동 선택 제공은 그대로 유지
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
- 출시 적합성 재검토(2026-09-15): `docs/release_audit/g6/recheck_2026_09_15/` — 원문 `release_readiness_review.md`(AUD-01~08), 조치 `fix_record.md`.
  공통 규칙이 된 것: 로딩 스피너 다이얼로그는 `runWithBlockingProgress`(`lib/utils/blocking_progress.dart`, `Navigator.pop(context)`로 닫지 말 것) ·
  시스템 알람 볼륨 변경은 `AlarmStreamVolume.kt` holder로만 · 울림 지속시간은 `CustomAlarmReceiver.ringDurationMinutes` 하나 ·
  "오늘" 날짜가 필요한 provider는 `currentDateProvider` 구독 · 프로세스 종료 전 `RingingAlarmTracker.runIfNoLiveRing`.
  `analysis_options.yaml`은 `docs/**` 제외. AUD-04(백그라운드 울림 지속, FGS 없음)는 코드 미수정·실기기 게이트
- 사용자 실기기 절차: 바탕화면에 문서 2개(2026-09-15 15개→8개 축소 후, PC 필요 여부로 3차 분리).
  `교대시계_출시전_필수_실기기테스트.txt` = PC+USB 필요(업데이트·재설치·백업복원·Play 내부 테스트, 4개).
  `교대시계_실기기테스트_폰단독.txt` = 지금 설치된 테스트 앱으로 폰만으로 바로 실행(매일 알람·미리듣기·
  충전기 뺀 하룻밤·권한 제한, 4개). 왜 이 8개만 실기기가 필요한지·나머지 7개가 왜 자동 테스트로 충분한지의
  전체 근거는 PC 문서 상단/하단에만 있음(폰단독 문서는 요약만 하고 PC 문서를 가리킴).
- 미검증: 홈 위젯 실기기 표시, G4 백업·복원 실제 실행, G5 prod release 광고·Analytics 목적지, 재검토 AUD 수정분 전부(실기기)
