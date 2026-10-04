# Shiftbell (교대시계) 프로젝트 가이드

교대 근무자를 위한 알람/근무일정 앱. Flutter + Kotlin Native.
Play Store 배포중 — **현재 운영 버전 `v1.0.23+25`** (태그 `v1.0.23`, `main`).
dev에는 1.0.24 기능 A~E와 후속 개선 작업이 있으며, 출시 전까지 `pubspec.yaml`의 버전은 `1.0.23+25`일 수 있다.

> 값(버전/개수/경로)을 인용하기 전에 실제 파일을 한 번 확인하세요.
> 2026-09-14에 루트의 옛 설계/검토 문서 20개를 정리해 핵심만 이 문서 **"설계 기록"** 절로 옮겼습니다.
> 코드 주석에 남아 있는 옛 문서 이름(`컨디션매니저_설계.md`, `백업복구_설계.md`, `DB_스키마_변경_가이드.md` 등)은
> 더 이상 존재하지 않으니 이 문서의 해당 절을 보세요.

> 2026-10-04부터 현재 제품 결정·진행 상태·잔여 검증은 [교대시계 최신 문서](docs/next_version/교대시계_최신문서.txt) 하나에만 갱신합니다. 날짜별 인계/계획/중복 요약을 만들지 않습니다. 아래 기술 설명과 과거 감사의 중간 상태가 충돌하면 최신 문서의 현재 결정을 우선합니다. 원장 CSV·로그·캡처는 증거로 보존합니다.

---

## 브랜치 / 릴리스 규칙

| 브랜치 | 역할 |
|--------|------|
| `main` | **배포된 코드만.** 릴리스할 때만 dev에서 병합하고 `vX.Y.Z` 태그를 붙임 |
| `dev` | 기본 작업 브랜치. 다음 버전 작업은 전부 여기서 |

- 릴리스 절차: dev에서 버전 bump → 빌드/검증 → `main`에 병합 → `git tag -a vX.Y.Z` → push (태그도 같이 push)
- **버전은 두 곳을 같이 올려야 함**: `pubspec.yaml`의 `version:`, `android/app/build.gradle.kts`의 `versionCode`/`versionName`
- 배포·공휴일 추가 절차: [최신 문서 E절](docs/next_version/교대시계_최신문서.txt) (운영 빌드는 광고 ID 주입 필수 — 아래 "광고" 참고)
- 다음 버전 작업 뒤에는 최신 문서의 해당 현재 상태·남은 조건·증거를 갱신한다. 옛 날짜별 문서를 재생성하지 않는다.

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
  - `friend_schedules` 친구 근무표(익명 UID 문서) / `app_config` 업데이트 안내(읽기 전용) / `health_tips`는 2026-09-15 범용 Tip 삭제로 앱이 읽지 않고 규칙에서도 빠짐(콘솔 게시본 = 저장소 `firestore.rules`, 2026-09-23 대조)
  - 규칙: `firestore.rules` — 운영 규칙과 같은 소유권·list 차단을 유지한다. 앱의 읽기 디코더는 중첩 값 오류를 거부한다.
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
- **셀 줄 맞춤(2026-09-23)**: 실험 테마 셀은 근무 칩·빨간날/음력 줄을 내용이 없어도 같은 높이로 비워 둠(`_redDaySlot`, `Visibility(maintainSize)`) —
  같은 주에서 메모 시작 줄이 날마다 틀어지지 않게. 다크 그리드의 오늘 표시는 셀 전체 노란 배경 → 날짜 숫자만 네이비 사각 배지
- 날짜별 **메모**, **OT/특근**, 근로시간·급여 산정(`work_hours_calculator.dart`)
- 공휴일 표시 (`holiday_util.dart` + `CalendarWidgetHolidays.kt` — **둘 다 같이 갱신**, 영어 로케일에서는 공휴일 표시 안 함)
  - 앱은 `app_config/holidays_kr` 변경분을 설치별 첫 0~7일에 분산 확인하고 성공 후 14일마다 다시 읽어 기본 목록에 덮어쓴다. 웹은 공휴일 Firestore를 읽지 않고 Dart 기본 목록만 쓴다. 신규·기존 날짜 수정과 앱/웹 배포는 `docs/next_version/교대시계_최신문서.txt` E절을 따른다. 위젯 Kotlin 기본 날짜도 함께 맞춘다.
- **원터치 알람(1.0.24)**: 달력 헤더 오른쪽 설정 칸 5개(`custom_alarm_widgets.dart`, 설정값 `custom_alarm_presets`). 내부 DB type은 호환성을 위해 `custom` 유지. 오늘·내일에만 추가하며 한 칸은 날짜별로 한 번만 할당한다(그날 원터치 최대 5개). 고정과 합친 하루 상한은 없다. `alarms.preset_slot`과 `assigned_day`가 설정 칸의 연결을 유지한다. 할당된 칸은 수정하지 못하며, 칸 삭제는 연결된 미래 알람을 함께 삭제한다.
  `CustomAlarmService.assign`은 DB 커밋 뒤 OS 예약, 실패 시 행과 생성 로그를 되돌린다. 같은 날짜·분에 먼저 있는 알람이 이긴다. Dart/Kotlin 고정 재생성은 원터치가 차지한 시각을 일시적으로 건너뛰고, 원터치 삭제 뒤 유효한 고정을 재계산·예약한다. 재부팅 때 원터치를 재등록한다. 스누즈가 다른 알람과 같은 분이면 스누즈를 만들지 않고 현재 알람을 종료한다. 화면과 이력에는 "원터치 알람"으로 표시한다.

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
`update_service.dart` — Google Play 인앱 업데이트 API로 이 기기에 제공되는 버전을 확인한다. 앱 시작·포그라운드 복귀 때 시도하고 성공한 확인 뒤 6시간 쿨다운, 버전코드별 안내 1회. Play 전파/단계적 배포 지연에 보장된 상한은 없다. 새 앱은 업데이트 확인용 Firestore를 읽지 않는다. 구버전 1.0.23은 계속 읽으므로 운영 `app_config/android` 문서를 제거하지 않는다.
"업데이트 후 첫 실행" 릴리즈 노트 팝업은 `_releaseNoteVersion`이 `''`이면 안 뜸(1.0.23은 사용자 결정으로 끔 — 켜려면 버전 문자열 + ARB 문구 교체).
1회성 안내 팝업은 `onboarding_info_popups.dart`의 4개(웰컴/불규칙 배정/일정관리 탭/수면·회복 탭)뿐, 각각 평생 1회 플래그.
**2026-09-22 — 네 팝업 모두 `kInfoPopupDelay`(700ms) 뒤에 뜬다**(공용 `_showInfoPopupOnce`). 홈은 `IndexedStack`이 아니라 현재 탭 하나만 트리에 올려서, 예전엔 탭에 처음 들어가 첫 프레임이 그려지자마자 모달이 덮었다. ⚠️ 플래그는 **띄우기 직전에** 세운다(예전엔 맨 처음) — 지연 중 탭을 옮기면 안 본 팝업이 "봤음"으로 기록돼 영영 안 뜨기 때문. 지연 뒤 context가 죽었거나 다른 화면/대화상자가 위에 있으면 건너뛰고 플래그를 그대로 둬 다음 진입 때 다시 시도(`test/onboarding_popup_delay_test.dart`).

### 관리자 대시보드 / 사용 통계 계측 (2026-09-22)
- **`admin_dashboard/`** — 개인용 운영 현황 웹(Firebase Hosting 별도 사이트 `shiftbell-ops-29f31`, 무료 한도). **aab에 안 들어감**(pubspec assets 아님).
  구조·1회성 설정·보안은 `admin_dashboard/README.md`. GA4 속성 `553838010`의 **prod 안드로이드 스트림 `15763725797`만** 집계
  (dev `15763791924`·웹 `15763713126` 제외 — `sync/lib/ga4.mjs`, 테스트로 고정). 운영 반영(Auth 설정·관리자 계정·규칙 게시·호스팅 배포·시크릿)은 사용자가 직접 함
- 알람 사용량 커서 `analytics_alarm_history_cursor`는 기기별 설정(`kDeviceLocalPreferenceKeys`) — 백업·복원 대상 아님(다른 기기 이력 ID와 안 맞음)
- 앱 쪽은 `lib/services/app_analytics.dart`뿐: `AppAnalytics.track(AnalyticsEvent.x, params: {...})`. **파라미터에 내용(근무표·메모·시각·이름)을 넣지 말 것** —
  종류/개수/탭 이름 같은 분류값만(방침 문구와 일치해야 함). 웹·dev에서는 아무것도 안 보냄
- 알람 끄기/연장/무응답은 Native 경로에 Firebase를 넣지 않고 `alarm_history`에서 **앱을 열 때** 새로 쌓인 것만 보냄(`AlarmUsageAnalytics.reportNew`) → 대시보드에는 며칠 지연될 수 있음
- ⚠️ 이벤트를 추가/개명하면 `AnalyticsEvent.all`과 `admin_dashboard/public/assets/js/labels.js` `EVENT_META`(+`mock.js`)를 같이 고칠 것 — `test/app_analytics_test.dart`가 두 목록 일치를 검사
- 대시보드 읽기 규칙은 루트 `firestore.rules`의 `dashboard/{doc}`(관리자 이메일 + `email_verified`). **콘솔에서 규칙을 게시할 때 이 블록이 빠지지 않게** 할 것(규칙 파일이 프로젝트에 하나뿐이라 대시보드도 이 저장소에 둠)
- Firebase 인증은 비밀번호 6자 이상(4자리 불가). 관리자 계정은 `sync/admin-user.mjs`(emailVerified:true)로만 만듦. ⚠️ 콘솔 Authentication → 설정 → 사용자 작업의 **"생성 사용 설정(가입)"은 켜 둘 것** — 끄면 익명 가입도 막혀 친구 공유가 새 기기에서 깨짐(2026-09-23 발생·복구, 규칙이 email_verified로 대시보드를 지키므로 켜도 안전)
- 동기화: GitHub Actions `dashboard-sync`(3시간마다) + Secret `GA4_SERVICE_ACCOUNT_JSON` = 전용 서비스 계정 `dashboard-sync@`(GA4 뷰어 + Cloud Datastore 사용자, 2026-09-23 등록). prod 데이터가 0건이면 빈 문서를 쓰고 성공(기존 데이터가 있으면 덮어쓰지 않고 실패)

### 수면·회복 탭 (구 컨디션 매니저, 2026-09-15 범위 축소)
`lib/screens/condition_tab.dart` + `lib/services/condition/*` — 하단 탭 이름은 "수면·회복"(클래스·provider·저장 키 `condition_tab_enabled`는 호환 위해 그대로).
영어 로케일은 `lib/screens/english_condition_tab.dart`에서 수면 기록·자동 추정 확인과 근무 전후 시각·확인된 수면 기록 요약을 제공한다. 한국어 추천 엔진 문장은 영어 화면에 노출하지 않는다.
한국어 화면: **오늘의 컨디션**(`recovery_briefing_engine.dart` — 지금 시각 기준 확인된 사실 / 시각이 박힌 추천 행동 최대 3개 / 판단 범위) +
자동 기록 확인 카드 + 최근 수면 기록 미니 달력(근무시간 입력 전에도 기록 가능). **컨디션 점수·범용 건강 Tip·날짜 시드 문구 엔진은 삭제**.
원칙 요약은 [최신 문서 B절](docs/next_version/교대시계_최신문서.txt)의 "수면·회복 유지 원칙"을 참고한다. 세부 규칙과 근거 ID는 `condition_rule_engine.dart`, `evidence_database.dart` 및 관련 테스트를 새 판정·행동을 넣기 전에 확인한다.

### 실제 수면 기록 / 자동 수면 추정
위젯 수동 기록(1순위) + 근무 일정·화면 장기 꺼짐 기반 자동 추정(2순위, 사용자 확인 필요). 세부 귀속·겹침 규칙은 `sleep_day_slots.dart`, `sleep_overlap.dart`와 관련 테스트를 참고한다.

### 백업/복구 (2026-09-14 G4로 재작성)
- **내보내기** `backup_service.dart`: 모든 테이블을 한 읽기 트랜잭션에서 `sqlite_master` 자동 스윕 → JSON 파일 하나.
  무엇을 넣고 뺄지는 `backup_policy.dart` 한 곳 — `alarms`는 **미래 custom만**(fixed 파생·snoozed D5 제외),
  친구공유 7키·설치별 설정(백업 상태·권한 요청·업데이트 안내) 제외. **새 원본 테이블/설정은 코드 수정 없이 자동 포함**
  (파생 데이터 테이블만 제외 목록에 추가할 것)
- **자동 백업** `backup_watcher.dart`: 시작·재개·배경 전환 때 내용 지문이 다를 때만, single flight, isolate 인코딩,
  네이티브 백그라운드 I/O, MediaStore `IS_PENDING`으로 완성 후 공개(#18). 복원 중/중단 작업이 있으면 안 씀
- **저장소**: MediaStore `Download/ShiftBell/ShiftBell_Backup[_dev]_{manual|auto}_yyMMdd_HHmmss.json` — **1.0.24~ 두 슬롯: 직접 백업 1개 + 자동 백업 1개**,
  새로 쓰면 같은 종류만 교체(`BackupFileNaming.kt`, 공개 전 다시 읽어 확인). 1.0.23의 "최신 + 직전 정상본(X-07)" 규칙과 옛 형식 파일은 첫 새 자동 백업 때 정리.
  (예전: `ShiftBell_Backup[_dev]_YYMMDD_HHmm.json`, 최신 + 직전 1개)
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
| DB 스키마 버전 | `DatabaseHelper.kt` `DATABASE_VERSION` (현재 **25**) | `database_service.dart` `version:` |
| DB SQL 원본 목표 버전 | `DatabaseHelper.kt` `DATABASE_VERSION` | `assets/db/migrations.json` `"targetVersion"` |
| 갱신 윈도우 일수 | `AlarmRefreshEngine.kt` `DAYS_AHEAD` (현재 **10**) | `alarm_limits.dart` `kAlarmRefreshWindowDays` |
| 수면 감지 창 경계값 4개 | `SleepScheduleResolver.kt` 야간 종료 전·일반 시작 시·최대 창·출근 전 낮잠 선행 | `sleep_opportunity.dart` 대응 상수 |

새로 이런 쌍이 생기면 `checkPair()`를 추가할 것(주석으로 "맞출 것"은 세 번 실패한 방법). hot reload로는 안 걸리니 스키마 변경 후엔 전체 빌드 1회.
빌드 가드가 못 잡는 계산 분기(공통 사례 테스트 필요): 알람 생성 계산(`alarm_generation_service.dart`↔`AlarmRefreshEngine.kt`),
수면 감지 창(`sleep_opportunity.dart`↔`SleepScheduleResolver.kt`), 공휴일(`holiday_util.dart`↔`CalendarWidgetHolidays.kt`). 수면 창의 숫자 경계 4개는 위 빌드 가드가 확인한다.

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

## DB 스키마 (v25)

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
- v25 `alarms.preset_slot`/`assigned_day`(원터치 설정 칸과 할당 날짜 연결) + `idx_alarms_preset_slot`.
  기존 알람 행의 두 컬럼은 NULL로 유지하고, 신규 원터치 할당부터 연결 정보를 기록한다.

---

## 설계 결정과 운영 기록

변경 이유·현재 결정·출시 전 남은 일과 미검증 절차는 [최신 문서](docs/next_version/교대시계_최신문서.txt)에 둡니다. 이전 출시 감사의 세부 근거는 `docs/release_audit/`에 있으며, 통합 전 루트/next_version 문서 원본은 `artifacts/document_cleanup_2026-10-04/original_documents.zip`에 보관합니다.
