# Shiftbell (교대시계) 프로젝트 가이드

교대 근무자를 위한 알람/근무일정 앱. Flutter + Kotlin Native.
Play Store 배포중 — **현재 운영 버전 `v1.0.22+24`** (태그 `v1.0.22` = `main`).

> 이 문서는 2026-08-24 기준으로 실제 코드를 읽고 다시 작성했습니다.
> 값(버전/개수/경로)을 인용하기 전에 실제 파일을 한 번 확인하세요.

---

## 브랜치 / 릴리스 규칙

| 브랜치 | 역할 |
|--------|------|
| `main` | **배포된 코드만.** 릴리스할 때만 dev에서 병합하고 `vX.Y.Z` 태그를 붙임 |
| `dev` | 기본 작업 브랜치. 다음 버전 작업은 전부 여기서 |

- 릴리스 절차: dev에서 버전 bump → 빌드/검증 → `main`에 병합 → `git tag -a vX.Y.Z` → push (태그도 같이 push)
- **버전은 두 곳을 같이 올려야 함**: `pubspec.yaml`의 `version:`, `android/app/build.gradle.kts`의 `versionCode`/`versionName`
- 자세한 배포 체크리스트: `업데이트_가이드.md`

---

## 기술 스택

- **Flutter (Dart)** + **Riverpod** 상태 관리
- **Kotlin Native (Android)** — 알람 실행, 홈 화면 위젯, 부팅/자정 갱신
- **SQLite (sqflite)** — **Device Protected Storage**에 저장 (잠금 해제 전에도 알람이 동작해야 하므로)
- **MethodChannel** — `com.hwani1103.shiftbell/alarm` (⚠️ `com.example`이 아님)
  - 채널 이름은 `lib/constants/platform_channel.dart`의 `kAlarmChannel` **하나만** 사용할 것. 리터럴 문자열 금지
- **Firebase** — Firestore만 사용 (Analytics/Messaging 등 없음)
  - `friend_schedules` : 친구 근무표 공유 (익명 인증 `ownerId` 기반)
  - `app_config` : 업데이트 안내용 원격 설정 (읽기 전용, 값은 콘솔에서 직접 수정)
  - 규칙: `firestore.rules`
- **i18n** — 한국어(원본) / 영어. `lib/l10n/app_ko.arb`(템플릿) + `app_en.arb`
  - `lib/l10n/generated/`는 **생성물이라 커밋 대상 아님** (`.gitignore`, `l10n.yaml` 참고)
  - 화면 코드에서는 `context.l10n.<key>` (`lib/l10n/l10n_extensions.dart`)

### 빌드 flavor (dev / prod)

정식 앱과 테스트 앱을 **한 기기에 동시에** 설치할 수 있게 분리되어 있음. dev는
`applicationId`에 `.dev` 접미사가 붙어 완전히 다른 앱으로 취급되므로, DB/설정도
분리되고 스토어 설치본을 절대 덮어쓰지 않음.

```bash
flutter install --release --flavor dev        # 테스트 설치
flutter build appbundle --release --flavor prod   # 스토어 배포용
```

> ⚠️ **flavor 없이 `flutter run`/`install`을 돌리면** 서명이 달라 스토어 설치본이
> "Uninstalling old version..."과 함께 **삭제**될 수 있음. 반드시 flavor를 지정할 것.

---

## 구현된 기능

### 알람
- 규칙적/불규칙 근무 스케줄, 근무별 알람 템플릿 (근무당 최대 **5개** — `kMaxAlarmTemplatesPerShift`)
- **10일치** 롤링 자동 생성/갱신 (`kAlarmRefreshWindowDays` ↔ Kotlin `DAYS_AHEAD`)
- 잠금 화면(`AlarmActivity`) / 해제 상태(`AlarmOverlayService`) 분기 실행
- 20분 전 사전 알림, 스누즈(5분), 타임아웃 자동 종료(지속시간은 **알람 타입별 DB 값**)
- 알람음 7종 + 제조사 시스템 알람음, 볼륨 보정(`VolumeCalibration.kt`)
- 알람 이력/생성 로그 영구 보존 (`alarm_history`, `alarm_creation_log`)

### 달력 / 근무
- 달력 탭, 전체 근무표(`all_shifts_view`), 날짜별 근무 변경
- **달력 테마 9종** (`lib/models/calendar_theme.dart`) — 앱과 홈 화면 위젯 양쪽에 반영
- **근무명 색상 직접 지정** — 테마 디폴트 위에 사용자 오버라이드를 얹는 구조 (`effectiveShiftColors()`)
- 날짜별 **메모**, **OT/특근** 기록, 근로시간·급여 산정(`work_hours_calculator.dart`)
- 공휴일 표시 (`holiday_util.dart` / `CalendarWidgetHolidays.kt`)

### 홈 화면 위젯
`CalendarWidgetProvider.kt` — 달력 + 근무색 + 메모까지 표시. 앱의 테마 설정을 따라감.

### 친구 공유
- 내 공유 코드 발급(`my_share_code_screen`), 친구 근무표 열람(`friend_calendar_view`)
- 웹 뷰어(`lib/web_main.dart` + `web/`) — 카카오톡 인앱 브라우저 대응 포함
- 스펙: `친구공유_v1_스펙.md`

### 업데이트 안내
`update_service.dart` — Play In-App Update API를 **쓰지 않음**(새 버전 전파 지연 때문).
Firestore `app_config`의 `latestVersionCode`를 앱이 직접 읽어 판단하고,
`minSupportedVersionCode`로 강제 업데이트도 가능(기본 비활성).
포그라운드 복귀 때마다 재체크하되 버전코드로 dedupe + 쿨다운.

---

## 파일 구조

```
lib/
├── constants/     alarm_limits · platform_channel · shift_name_limits
├── l10n/          app_ko.arb(템플릿) · app_en.arb · l10n_extensions
│                  generated/ ← 생성물, 커밋 안 함
├── models/        alarm · alarm_history · alarm_template · alarm_type
│                  shift_schedule · calendar_theme · date_memo
│                  date_overtime · friend_schedule
├── providers/     alarm · schedule · calendar_theme · friend · memo
│                  overtime · work_hours_settings
├── screens/       splash · onboarding · permission_intro
│                  calendar_tab · next_alarm_tab · settings_tab
│                  all_shifts_view · all_alarms_history_view · memo_list_view
│                  all_teams_setup_dialog · work_hours_settings_screen
│                  calendar_theme_picker_screen · calendar_theme_lab_screen
│                  friend_list_screen · friend_calendar_view · my_share_code_screen
├── services/      alarm_service · alarm_refresh_service · database_service
│                  permission_service · update_service · widget_refresh_service
│                  firebase_bootstrap · friend_share_service · friend_sync_service
│                  work_hours_calculator
├── theme/ utils/ widgets/
└── web_main.dart  친구공유 웹 뷰어 (Flutter Web 전용 엔트리)

android/app/src/main/kotlin/com/hwani1103/shiftbell/
├── MainActivity.kt                    MethodChannel 핸들러
├── AlarmActivity.kt                   잠금 화면 알람
├── AlarmOverlayService.kt             해제 상태 알람 오버레이
├── AlarmPlayer.kt / VolumeCalibration.kt
├── CustomAlarmReceiver.kt             알람 수신
├── AlarmGuardReceiver.kt              사전 알림 & 자정 감시
├── AlarmRefreshEngine.kt              ⭐ 10일치 갱신 본체 (DAYS_AHEAD)
├── AlarmRefreshReceiver.kt / AlarmRefreshUtil.kt / RefreshLockManager.kt
├── DirectBootReceiver.kt              재부팅 처리
├── AlarmActionReceiver.kt / AlarmActionHelper.kt / NotificationHelper.kt
├── DatabaseHelper.kt                  ⭐ Native DB 접근 (DATABASE_VERSION)
└── CalendarWidget{Provider,ScheduleResolver,Holidays}.kt
```

---

## ⚠️ 반드시 지켜야 할 것

### 1. Dart ↔ Kotlin 상수 동기화 (빌드가 강제함)

같은 값이 두 언어에 **각각 하드코딩**되어 있어 손으로 맞춰야 하는 쌍이 있음.
이게 세 번 어긋나서 위젯/알람이 조용히 멈춘 전례가 있어, 이제 **값이 다르면 빌드가 실패**함
(`android/app/build.gradle.kts`의 `checkDartKotlinSync`, 모든 variant의 preBuild가 의존).

| 값 | Kotlin | Dart |
|----|--------|------|
| DB 스키마 버전 | `DatabaseHelper.kt` `DATABASE_VERSION` (현재 **18**) | `database_service.dart` `version:` |
| 갱신 윈도우 일수 | `AlarmRefreshEngine.kt` `DAYS_AHEAD` (현재 **10**) | `alarm_limits.dart` `kAlarmRefreshWindowDays` |

새로 이런 쌍이 생기면 `checkPair()` 호출을 하나 더 추가할 것.

> 📌 **DB 스키마를 바꾸기 전에 `DB_스키마_변경_가이드.md`를 먼저 읽을 것.**
> 이 두 값이 어긋나면 앱은 멀쩡한데 **위젯/알람화면/알람갱신만 조용히 전부 죽는다**
> (예외도, 크래시도 없음). 실제로 세 번 재발했음. 증상 대조표와 변경 절차가 그 문서에 있음.

### 2. 알람 이력은 절대 자동 삭제 금지
`alarm_history` / `alarm_creation_log`는 영구 보존 테이블. 정리 로직을 넣지 말 것.

### 3. Device Protected Storage

```kotlin
val deviceContext = context.createDeviceProtectedStorageContext()
val prefs = deviceContext.getSharedPreferences("alarm_state", Context.MODE_PRIVATE)
```

```dart
final path = await kAlarmChannel.invokeMethod('getDeviceProtectedStoragePath');
```

Flutter의 `SharedPreferences`와 Native의 `alarm_state`는 **서로 다른 경로**임. 혼동 금지.

### 4. DB 마이그레이션 순서
Native(`DatabaseHelper.kt`)는 디스크 버전이 `DATABASE_VERSION`과 정확히 일치할 때만
DB를 건드림 — Flutter가 마이그레이션을 끝내기 전에는 스킵. 스키마를 바꿀 땐
Flutter `onUpgrade`와 Kotlin 상수를 같은 커밋에서 올릴 것.

### 5. 알람 갱신 트리거 지점
1. 알람이 울릴 때 (`CustomAlarmReceiver.onReceive`)
2. 자정 / 알람 20분 전 (`AlarmGuardReceiver`)
3. 알람 끄기·스누즈 (`AlarmOverlayService`)
4. 앱 실행 (`MainActivity.onCreate`)

---

## DB 스키마 (v18)

`shift_schedule` · `shift_alarm_templates` · `alarms` · `alarm_types` ·
`alarm_history` · `alarm_creation_log` · `date_memos` · `date_overtime` · `friends`

최근 변경:
- v17 — `friends`를 Firestore `ownerId` 기반으로 재설계
- v18 — `shift_schedule.custom_shift_colors` 추가 (근무명 색상 직접 지정)

---

## 참고 문서

| 파일 | 내용 |
|------|------|
| `DB_스키마_변경_가이드.md` | **DB 버전 올릴 때 반드시 읽을 것** — 언제 바꾸나, 세 번 재발한 사고, 절차/검증 |
| `업데이트_가이드.md` | 버전 올리고 배포하는 절차 |
| `친구공유_v1_스펙.md` | 친구 공유 설계 (Firestore 구조 포함) |
| `위젯_테마반영_스펙.md` | 홈 화면 위젯 테마 반영 규칙 |
| `교대시계_영어화_현지화_보고서_영문판.md` | i18n 결정 사항 |
| `코드_품질_검수_리포트_2026-08-14.md` | 검수 결과 (리뷰만, 수정은 별도) |
| `TEST_CHECKLIST.md` | 수동 테스트 체크리스트 |

---

## 알려진 상태

- `flutter analyze` — 에러 1건(`lib/web_main.dart`의 `dart:js_util`, **웹 빌드 전용**이라
  모바일 빌드엔 영향 없음), 경고 0건, 나머지는 info 린트
- 저장소 히스토리에 예전 logcat 덤프 86MB가 남아 있음(팩 16MB). 추적은 해제됨
- 미검증: 홈 화면 위젯 테마 반영은 코드상 완성이지만 실기기 확인 이력 없음
