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
- **Firebase** — Firestore + Analytics (2026-09-12부터, "교대시계 관리자" DAU/MAU
  1단계 - Messaging 등은 여전히 없음). Analytics는 Firestore/Auth와 달리
  `firebase_options.dart`의 `FirebaseOptions`만으론 동작 안 함 - `google-services.json`
  (`android/app/`, prod/dev 패키지명 둘 다 등록돼 있음) + `com.google.gms.google-services`
  Gradle 플러그인이 실제로 붙어 있어야 함(`친구공유_v1_스펙.md`에 이 플러그인을 한 번
  뺐다가 다시 붙인 경위 기록)
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
- 알람은 근무 배정일 기준 **전날/당일/다음날**(`day_offset`, -1/0/1) 중 골라서 등록 가능
  (예: 야간 근무 전날 저녁 알람). 같은 실제 시각에 다른 근무의 알람이 겹치면 물리적으로
  하나만 등록됨(우선순위: 당일 > 전날 기여 > 다음날 기여) — 계산은
  `lib/services/alarm_generation_service.dart` ↔ `AlarmRefreshEngine.kt`가 동일하게 유지
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

### 일정관리 탭 / 메모·일정 카테고리 자동분류
- `schedule_management_tab.dart` — 세로 시간축에서 시각을 골라 일정 생성/수정.
  `date_schedules` 테이블(v20, `date_memos`와 완전히 별개)에 영구 저장
- **일정에 맞춰서 알림받기**(2026-09-12) — 일정 생성/수정 시트의 스위치를 켜면
  정시(또는 5/10/30분 전, `notify_offset_minutes`)에 가벼운 일반 알림 1건이
  옴 - 기존 "알람"(잠금화면/벨소리/스누즈)과 무관, 소리/진동/무음은 이 알림
  전용 채널("일정 알림")의 시스템 기본값을 그대로 따름. 예약은 기존 알람과
  같은 방식(Native `AlarmManager`, `ScheduleNotificationScheduler.kt`/
  `ScheduleNotificationReceiver.kt`) - 재부팅 시 `DirectBootReceiver`가
  `date_schedules`를 직접 읽어 재예약함. 알림을 탭하면 일정관리 탭으로 이동해
  그 일정의 시간대로 자동 스크롤(`lib/utils/schedule_focus_request.dart`).
  DB v23(`notify_enabled`/`notify_offset_minutes`), 등록/취소는
  `date_schedule_provider.dart`의 create/update/delete 세 지점뿐 -
  `전체근무표_개선안_및_일정알림_설계메모.md` 2장 참고
- 일정 생성 시 아이콘을 직접 안 고르면 내용 텍스트로 자동분류해서 카테고리
  아이콘을 대신 배정(`MemoCategoryClassifier`, 키워드 하드매핑 + 온디바이스
  TF-IDF/LogisticRegression, `assets/ml/memo_category_model.json`) — 직접 고르면
  항상 그 선택이 우선. 모델 학습/재export는 `ml/`(Python) 참고
- 카테고리 **25종**(2026-09-01, 기존 10종에서 확장 — 달리기/수영/등산/문화생활/
  금융/집안일/미용 신설. 2026-09-03, 자전거/요가·필라테스 추가 신설. 2026-09-12,
  "운동"에서 세분화 — 라켓 스포츠/축구/농구/야구/구기종목/입식 격투기 6종
  신설, 신규 6종은 전부 하드매핑 전용이라 ML 재학습 없이 동작). 정의/
  우선순위는 `ml/카테고리_가이드.md`, 아이콘 매핑은
  `assets/icons/memo_category/README.md` 참고
- 상세: `메모_자동분류_ML_계획.md`(Phase 0~5 완료, Phase 6~7 보류, Phase 8
  카테고리 확장 완료)

### 친구 공유
- 내 공유 코드 발급(`my_share_code_screen`), 친구 근무표 열람(`friend_calendar_view`)
- 웹 뷰어(`lib/web_main.dart` + `web/`) — 카카오톡 인앱 브라우저 대응 포함
- 스펙: `친구공유_v1_스펙.md`

### 업데이트 안내
`update_service.dart` — Play In-App Update API를 **쓰지 않음**(새 버전 전파 지연 때문).
Firestore `app_config`의 `latestVersionCode`를 앱이 직접 읽어 판단함.
포그라운드 복귀 때마다 재체크하되 버전코드로 dedupe + 쿨다운.
강제 업데이트(`minSupportedVersionCode`) 기능은 2026-09-12에 안 쓰기로 하고 제거함.

### 컨디션 매니저 (1차 버전 — 신설 탭, "일정관리" 옆)
`lib/screens/condition_tab.dart` + `lib/services/condition/*` — 교대근무 일정을
분석해 수면/피로 부담에 대한 **근거 기반** 조언을 주는 기능. 기존 UI에 얹지
않고 독립 탭으로 시작(설정 탭 미변경). 핵심 원칙: 숫자 점수·%·질병 진단
절대 금지, 상태는 `NORMAL`/`ATTENTION`/`HIGH_LOAD` 3단계만, 모든 판정은
Evidence ID로 추적 가능해야 함(AI가 임의 판단 금지).

> 📌 **예외**: `lib/services/condition/condition_score.dart`(+ `condition_tab.dart`의
> "컨디션 점수: N점" 표시)는 위 "숫자 점수 절대 금지" 원칙에 대한 **사용자
> 요청으로 승인된 유일한 예외**임(설계 근거: `컨디션매니저_설계.md` 19장).
> `ConditionRuleEngine`의 3단계 판정(`NORMAL`/`ATTENTION`/`HIGH_LOAD`) 자체는
> 이 예외로 바뀌지 않았고, 점수는 그 판정 위에 별도로 얹힌 보조 표시임 -
> 새 화면/기능에 점수·%·진단을 또 추가해도 되는 선례로 오독하지 말 것(이
> 예외는 딱 이 한 곳에만 적용됨).

- `ShiftPatternAnalyzer`(`shift_pattern_analyzer.dart`) — 근무 패턴 분석
  엔진(연속 야간/연속 근무일, 근무 사이 회복시간, 교대 방향, 주간 요약). 기존
  `ShiftSchedule`을 그대로 읽고 수정하지 않음
- `ConditionRuleEngine`(`condition_rule_engine.dart`) — **2026-09-04 v2(+후속)**:
  Evidence 기반 신호 5개가 상태를 판정. 회복시간<11h(EV-002/003)·근무≥12h(EV-004)·
  최근 7일 초과근무≥8h(EV-012)·역방향 교대(EV-001)·연속 야간근무≥3일(EV-013)
  5개는 개별로 `ATTENTION`, 이 중 **2개 이상 겹치면** `HIGH_LOAD`
  (`RULE_COMPOUND_HIGH_LOAD` — "겹치면 심각"이라는 조합 자체는 논문 수치가
  아니라 이 앱의 설계 판단, 개별 신호의 근거는 각자 인용). 그 중 2개는 근거가
  특히 강해 그 자체로 단독 `HIGH_LOAD`: 장시간근무 3일 이상 연속+짧은 회복
  (EV-004/005, v1과 동일), 연속 야간근무 4일 이상(EV-013 - 원 연구가 "이
  시점부터 가속화"라고 명시하는 구간). 대응하는 Evidence 항목이 없는 순수
  계산값(연속 근무일수 자체 등)은 여전히 판정에 안 쓰고 설명(context)에만
  사용 — "여기 없는 근거는 어떤 Rule에도 안 쓴다"는 원칙 자체는 유지.
  `evaluate()`가 이제 `otMinutesByDate`를 받음(기본값 빈 맵 — 안 넘기면
  RULE_WEEKLY_OVERTIME은 항상 꺼짐, 실제 배선은 `condition_provider.dart`의
  `todayConditionResultProvider` 참고). `condition_score.dart`도 새 신호를
  반영(연속 야간근무 -10, 4일 이상 추가 -10). 상세: `컨디션매니저_설계.md`
  22~23장
- `evidence_database.dart` — NIOSH/AASM/EU Working Time Directive/National
  Sleep Foundation/Folkard & Tucker 등 13개 Evidence, 원문 근거자료는
  `컨디션매니저_근거자료.md`
- **"오늘의 컨디션 예측"(킬러 기능, 2026-09-01 추가)** — 탭 맨 위 카드
  (`_TodayForecastCard`). 최근 최대 8주(56일)의 근무시간 추세 + 실제 수면
  기록(있는 만큼만)을 `today_forecast_engine.dart`가 종합해 2~3문장으로 예측.
  ML/임베딩이 아니라 **조합형(축마다 상태 분류 + 변주 풀 + 결정론적 로테이션)**
  규칙 엔진 - 이 기능 자체는 `ConditionRuleEngine`의 판정에 문구만 덧붙이는
  별도 표시 레이어(2026-09-01 추가 당시엔 "0줄 수정"이었으나, 2026-09-04 v2에서
  `ConditionRuleEngine`이 이 레이어가 이미 쓰던 OT 데이터를 판정에도 쓰게
  되면서 더는 완전히 무관하지 않음 — 다만 이 레이어의 문구 생성 로직 자체는
  안 바뀜). **개인 평소 근무시간**(`personalBaselineShiftMinutes`,
  최근 8주 평균)도 이 문구 레이어에서만 반영 — "어제/오늘 근무가 이 사람
  기준으로 평소보다 긴가"를 절대 기준(11~12시간)과 별개로 추가 비교함
  (`RULE_LONG_SHIFT`의 12시간 EVIDENCE-004 절대 기준은 안 건드림 — 습관화
  여부와 무관한 연구 근거값이라 개인 상대 비교로 왜곡하면 안 됨). 상세/다음
  단계는 `컨디션매니저_설계.md` 13장(13-8이 인계 노트)/14장.
- 근무명별 출퇴근 시각(`condition_shift_times` 테이블, v21) 입력은 **설정 →
  근무시간 및 OT 설정**(`work_hours_settings_screen.dart`)에서 함(2026-09-01
  변경 — 원래는 이 탭 안에서 직접 받았으나 이동함). 그 화면이 원래 받던
  근무별 "시간(분)"(`shift_schedule.shiftDurations`, 근로시간/OT 계산용)을
  출퇴근 시각 입력으로 바꾸고 `ShiftTimeRange.durationMinutes`로 자동 계산해서
  같은 값을 채움 — 입력 한 번으로 두 데이터를 같이 얻음. 사용 중인 근무명
  **하나라도** 시각이 입력돼 있으면 이 탭이 동작함(전부 다 채울 필요 없음) —
  안 채워지면 탭 전체가 안내 문구 하나만 보여줌
- 상세: `컨디션매니저_설계.md`(아키텍처/UI, 11장에 이 변경 기록), `컨디션매니저_근거자료.md`
  (근거자료 조사, Evidence ID 매핑)

### 실제 수면 기록 및 자동 수면 추정 ("C번 요구사항", 컨디션 매니저 위에 얹은 신규 기능)
사용자가 직접 위젯에서 취침/기상을 기록하거나(1순위), 근무 일정 + 휴대폰 장기
미사용을 기반으로 자동 추정(2순위, 항상 사용자 확인 필요)한다. 근무시간과 겹치는
수면(야간근무 중 가수면 등)도 validation 없이 정상 저장하고, 조회 시점에만
"근무 중 수면"으로 분류한다. 상세 조사/설계는 `수면기록_자동추정_조사.md`
(Android 배경 감지 기술 검토), `수면기록_자동추정_설계.md`(아키텍처) 참고.

- 위젯: `SleepWidgetProvider.kt`/`SleepWidgetActionReceiver.kt` — 홈 화면 캘린더
  위젯(`CalendarWidgetProvider.kt`, 수정 없음)과 **완전히 별개**의 위젯. "오늘: OO"
  (근무명)/"상태: OO"(활동 중/수면 중/수면 중으로 추정) 두 줄 +
  "🌙 수면"/"☀️ 기상" 버튼 2개(2026-09-01 재설계 — 토글 버튼 1개는 지금 상태가
  뭔지 헷갈린다는 피드백으로 명시적 버튼 2개로 바꿈). **2026-09-05 — "오늘 수면
  (N시간)" 기상 후 요약 표시는 삭제함** — 근무 연관 없이 "가장 최근 완료 기록"만
  보고 판단해서, 컨디션 탭(날짜/근무 연관까지 정확히 분류)과 같은 기록을 서로
  다르게 설명하는 모순이 있었음(예: 야간 후 아침잠을 위젯은 "오늘 수면"으로,
  컨디션 탭은 "어제 야간의 주 수면"으로 표시) — 위젯은 "지금 자고 있는지"만
  빠르게 보여주는 원래 목적에 집중, 실제 수면시간/근무 연관 분류는 컨디션 탭·
  "최근 수면 기록" 미니 달력만 신뢰함. **MANUAL 뿐 아니라
  AUTO_DETECTED 진행 중도 "수면 중으로 추정"으로 반영**(2026-09-01 후속) — AUTO
  진행 중엔 "수면" 버튼은 무시(정확한 소급 시작시각을 덮어쓰지 않기 위함),
  "기상"을 누르면 그 자리에서 CONFIRMED로 확정(앱의 "맞아요"와 동일 효과).
  2분 미만 기록은 연타/실수 방지로 저장하지 않고 버림 — 상세: 수면기록_자동추정_설계.md 13-6장
- 자동 감지: 상시 화면 감시나 Foreground Service, 특수 권한(사용정보 접근) 없이,
  `AlarmManager` 기반으로 "수면 가능 시간대"에만 20분 간격 샘플링
  (`SleepDetectionScheduler.kt`/`SleepDetectionReceiver.kt`). 트리거는
  `AlarmGuardReceiver`/`MainActivity.onResume`/`DirectBootReceiver`에서
  `SleepDetectionReceiver.checkNow()`를 호출(2026-09-01 변경 — 원래는 다음 20분
  알람이 울릴 때까지 기다렸는데, 화면이 켜지는 이 트리거 시점에 즉시 판정하도록
  바꿔서 "기상 후 앱을 열어도 한참 진행 중으로 남는" 버그를 고침. 기존 로직
  자체는 변경 없음)
- 자동 감지 창은 "메인 잠 전용"으로 최대한 좁힘(2026-09-01 후속 재설계) — 야간
  근무는 종료 1시간 전부터, 그 외/휴무는 21시 이후부터만 열리고, 둘 다 최대
  9시간 캡(다음 근무 시작이 더 이르면 그걸로 컷). 근무 중 짧은 낮잠은 이 창에
  절대 포함 안 됨(위젯 수동 기록 전용). 이 로직은 `sleep_opportunity.dart`
  (Dart)와 `SleepScheduleResolver.kt`(Kotlin) 양쪽에 동일하게 유지해야 함
  (알람 생성 로직의 Dart/Kotlin 이중구현과 동일한 선례). ("근무별 평균 취침
  시각" 입력 기반 1순위 앵커는 2026-09-01에 삭제됨 — 수면기록_자동추정_설계.md
  12장/13-7장 참고)
- `SleepRecord`(`sleep_records` 테이블, 신규)는 분류 라벨을 저장하지 않고
  `sleep_shift_relation.dart`가 조회 시점에 근무 겹침 여부(근무 중 수면/주 수면/
  낮잠)를 매번 계산 — 근무 스케줄이 나중에 바뀌어도 과거 기록의 분류가 자동으로
  맞게 나옴
- **Sleep Detection과 컨디션 매니저(`ConditionRuleEngine`)는 완전히 분리** —
  `ConditionRuleEngine`은 이 기능 추가로 단 한 줄도 안 바뀜.
  `sleep_stats.dart`/`sleep_condition_provider.dart`가 별도로 "야간근무 후 평균
  수면" 등을 계산해서 화면의 별도 섹션에 얹을 뿐. 단, "오늘의 컨디션" 카드에는
  예외적으로 `sleep_condition_extras.dart`(신규, 순수 함수)가 계산한 보조 설명
  한 줄만 표시용으로 얹음(판정/레벨에는 영향 없음 — 컨디션매니저_설계.md 11장)
- **"최근 수면 기록" 미니 달력 카드**(2026-09-01, 컨디션 탭) — `sleep_day_slots.dart`가
  확정된 `SleepRecord`를 취침 시작 날짜 기준으로 묶어 하루 최대 3칸(주 수면 1칸
  + 낮잠 2칸 — 길이(4시간) 기준 자동 분류, 순수 표시 개념이라 DB 컬럼 아님.
  "근무 중 낮잠" 구분은 2026-09-01 후속에 삭제 — 낮잠 2칸 다 그냥 "낮잠")으로
  뽑고, 오늘까지만 가로 스크롤 카드로 보여줌. 칸을 탭하면 그 자리에서 기록
  생성/수정/삭제(`sleep_edit_dialog.dart` 공용 바텀시트, SafeArea+`AppSecondButton`
  적용). 더 과거 기록은 "전체보기"(`sleep_calendar_full_screen.dart`, 신규 화면, 리스트형
  으로 확정) — 월 단위 이전/다음 이동. 상세: 수면기록_자동추정_설계.md 13-3/13-6장

### 백업/복구 (기능 완성 — 새 데이터 도메인 만들기 전에 먼저 읽을 것)
`lib/models/backup_payload.dart` + `lib/services/backup_service.dart` — DB(`shiftbell.db`)
전체 테이블을 `sqlite_master`로 그때그때 자동 스윕해서 JSON으로 내보내고(`exportAll`),
빈 상태(재설치 직후)에서만 되돌려놓는(`restoreAll`) 순수 추가 레이어. **기존 파일은
0개 수정** — 알람 데이터/근무패턴/알람 갱신·발생·notification 로직은 전혀 안 건드림
(`alarms` 테이블은 파생 데이터라 백업 제외, 복구 후 기존 알람 갱신 로직이 알아서
재생성).

- **저장소**: 기기 로컬 `MediaStore`(Download/ShiftBell 폴더) 하나뿐 — 클라우드/
  Firebase/로그인 전혀 안 씀. Android 10(Q) 미만 미지원. Native 쪽은
  `MainActivity.kt`의 `writeBackupFile`/`readBackupFile`, Dart 쪽은
  `lib/services/backup_storage_service.dart`.
- **자동 백업**: `lib/services/backup_watcher.dart` — 앱이 background로 전환되는
  시점(`main.dart`의 `didChangeAppLifecycleState`)에만, `PRAGMA data_version`으로
  실제 변경이 있을 때만 씀(폴링 없음). 수동 "지금 백업"(설정 탭)도 같은 함수를
  `force: true`로 호출 - 자동/수동 표시가 항상 일치함.
  범위/한계는 `백업복구_설계.md` 13장 참고.
- **복구 UX**: `lib/screens/restore_backup_screen.dart` — 신규 설치(`schedule ==
  null`)시 기기에 백업이 있으면 `PermissionIntroScreen`(신규 설치 첫 화면)이
  온보딩 대신 이 화면으로 보냄. 복구 후엔 `permissions_requested`를 무조건
  `false`로 되돌려 OS 권한(알림/정확한 알람/오버레이)을 반드시 다시 받게 함 —
  백업 안의 그 플래그 값을 그대로 믿지 않음.
- **자동 탐지 실패 대비 수동 복구**: MediaStore 자동 탐지(`readBackupFile`)가
  일부 기기(확인된 사례: 삼성 - MediaStore 행의 `owner_package_name`이 NULL로
  남는 OEM 버그로 추정, 앱 코드로 못 고침)에서 실패할 수 있어 `PermissionIntroScreen`에
  "직접 불러오기" 링크로 시스템 파일 선택기(SAF) 경로를 항상 열어둠
  (`pickBackupFile` MethodChannel, `BackupStorageService.pickAndRead()`) —
  자세한 원인 조사는 `백업복구_설계.md` 참고.
- **알려진 미해결 갭**: Firebase 익명 인증 UID는 재설치하면 새로 발급됨 — 내가
  공유한 근무표를 보던 친구 쪽 연결이 끊김(범위 밖, 별도 과제).
- **수면/컨디션 등 새 원본 데이터 테이블을 추가하면 이 백업 레이어가 코드 변경 없이
  자동으로 포함시킨다** — 새 테이블/설정을 추가할 때 이 동작을 깨뜨리지 않으려면
  `백업복구_설계.md`를 먼저 읽을 것. 상세: `백업복구_설계.md`.

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
| DB 스키마 버전 | `DatabaseHelper.kt` `DATABASE_VERSION` (현재 **23**) | `database_service.dart` `version:` |
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

## DB 스키마 (v23)

`shift_schedule` · `shift_alarm_templates` · `alarms` · `alarm_types` ·
`alarm_history` · `alarm_creation_log` · `date_memos` · `date_schedules` ·
`date_overtime` · `friends` · `condition_shift_times` · `sleep_records` ·
`sleep_expected_bedtime`

최근 변경:
- v17 — `friends`를 Firestore `ownerId` 기반으로 재설계
- v18 — `shift_schedule.custom_shift_colors` 추가 (근무명 색상 직접 지정)
- v19 — `shift_alarm_templates`/`alarms`/`alarm_history`/`alarm_creation_log`에
  `day_offset`(전날 -1 / 당일 0 / 다음날 +1) 추가. 알람 생성 계산은
  `lib/services/alarm_generation_service.dart`(Dart)와
  `AlarmRefreshEngine.kt`(Kotlin)가 동일한 알고리즘을 유지해야 함(파일 상단 주석 참고)
- v20 — `date_schedules` 테이블 신설. 일정관리 탭(`schedule_management_tab.dart`)
  전용 CRUD — `date_memos`(달력 탭 메모)와는 완전히 별개. 메모 자동분류
  (`lib/services/memo_category_classifier.dart`, 메모_자동분류_ML_계획.md Phase 4~5)의
  카테고리 자동배정 결과를 `predicted_category`/`is_user_corrected`로 같이 기록
- v21 — `condition_shift_times` 테이블 신설. 컨디션 매니저(1차 버전) 전용 -
  근무명별 출퇴근 시각(자정 기준 분)만 저장. Native는 이 테이블을 전혀 안 읽음
- v22 — `sleep_records`/`sleep_expected_bedtime` 테이블 신설. 실제 수면 기록/자동
  추정 전용 - 이번엔 Native(SleepDetectionReceiver.kt 등)가 직접 읽고 씀
- (되돌려짐) v23 시도(1차) — "D번 요구사항"(일정관리 탭 일정 생성 팝업 5분
  미세조정)의 물리적 표시 위치를 `date_schedules.slot_minutes` 컬럼으로
  저장하려 했으나, `start_minutes`만으로 항상 계산 가능한 순수 파생값으로
  정정되어(`date_schedule.dart`의 `computeSlotMinutes()`) 마이그레이션을
  되돌림 - DB는 다시 v22.
- v23(2026-09-12) — `date_schedules`에 `notify_enabled`/`notify_offset_minutes`
  추가. 일정관리 탭 "일정에 맞춰서 알림받기" 실제 구현(그동안 UI만 있고
  DB 컬럼/예약 로직이 없던 목업 - `전체근무표_개선안_및_일정알림_설계메모.md`
  2장 참고). 이번엔 Native(`ScheduleNotificationScheduler.kt`)가 재부팅 재예약을
  위해 이 테이블을 직접 읽음 - v20/v21 당시의 "Native 미사용" 전제가 끝남.

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
| `메모_자동분류_ML_계획.md` | 온디바이스 메모/일정 카테고리 자동분류(`ml/`, TF-IDF+LogReg). Phase 4~5 완료 |
| `메모_일정기능_설계메모.md` | 일정관리 탭 시간 필드 확장 설계(미착수) — `date_schedules`(v20) 컬럼 추가 계획 시 참고 |
| `일정관리탭_UI_스펙.md` | 일정관리 탭 UI 현재 상태(색상 스킴, 일정생성 flow — FAB+시간배지+스크롤 오버슛/calibration, 스와이프 내비게이션) — 코드 손대기 전 참고 |
| `백업복구_설계.md` | 사용자 데이터 백업/복구 설계 + 구현 실적(레이어 1~4 전부 완료) — **새 원본 데이터 테이블/설정을 추가하기 전에 먼저 읽을 것**(자동 백업 대상에 자연히 포함되는 설계라, 깨뜨리지 않으려면 원본/파생 구분 원칙을 알아야 함) |
| `컨디션매니저_설계.md` | 컨디션 매니저(1차 버전) 아키텍처/UI/DB 설계 — Rule↔Evidence 매핑표, 기존 코드 영향 범위 |
| `컨디션매니저_근거자료.md` | 컨디션 매니저가 실제로 인용하는 근거자료(NIOSH/AASM/EU Working Time Directive 등) 원문 조사 — 새 rule/tip을 추가하기 전에 먼저 읽을 것(근거 없는 판정 금지 원칙) |
| `수면기록_자동추정_조사.md` | 실제 수면 기록/자동 추정 기능의 Android 배경 감지 기술 조사(화면 on/off 감시 방법별 기각/채택 이유, 배터리 영향) — 감지 방식을 바꾸기 전에 먼저 읽을 것 |
| `수면기록_자동추정_설계.md` | 위 기능의 아키텍처/DB/위젯/컨디션 매니저와의 분리 원칙 |
| `백업_수면_컨디션_기능_검토_2026-09-01.md` | 위 세 기능(백업/수면기록/컨디션매니저) 코드+UX 검토(리뷰만, 수정은 별도) — B1(연속 야간근무 시 자동 감지 창 계산 버그, HIGH)은 2026-09-04 재점검에서 Dart/Kotlin 양쪽 다 이미 고쳐져 있음을 확인함(아래 전체_코드_점검_리포트 참고), A2/A3/B3/C1은 여전히 미해결 |
| `전체_코드_점검_리포트_2026-09-04.md` | 알람/수면기록/컨디션매니저/백업·DB마이그레이션/주요 UI 화면/친구공유(Firestore 포함) 전면 재점검(리뷰만) — HIGH 3건(컨디션 탭 무한루프 위험, 알람갱신 트랜잭션 중 OS콜, 자동백업 감지 로직 결함) 최우선 |
| `세션_기록_2026-09-11.md` | 9개 UX 수정(전부 dev 미커밋) + 자동백업 재점검(dev/prod 파일명 충돌 수정, 근본원인 미확정) + 수면감지 거부학습 + "교대시계 관리자"(DAU/MAU) 앱 계획 1단계 착수 중 막힌 지점 기록 — 다음 세션 시작 시 먼저 읽을 것 |
| `테스트_계획_2026-09-12.md` | 라운드 기반 탐색적 수동 테스트(A) + 자동화 테스트 인프라(B: Kotlin/Robolectric) 계획. `integration_test/`(Flutter E2E)는 2026-09-13 환경 제약(호스트 RAM 6GB)으로 코드까지 제거함 — 아래 "알려진 상태" 참고. 진행 경과/PASS·FAIL 기록은 바탕화면 `테스트_진행상황.txt`(라운드별로 계속 갱신, 저장소 밖) |

---

## 알려진 상태

- `flutter analyze` — 에러 1건(`lib/web_main.dart`의 `dart:js_util`, **웹 빌드 전용**이라
  모바일 빌드엔 영향 없음), 경고 0건, 나머지는 info 린트
- 저장소 히스토리에 예전 logcat 덤프 86MB가 남아 있음(팩 16MB). 추적은 해제됨
- 미검증: 홈 화면 위젯 테마 반영은 코드상 완성이지만 실기기 확인 이력 없음
- 2026-09-12 - 이 프로젝트 최초의 Kotlin 테스트(`android/app/src/test/kotlin/...`,
  JUnit4+Robolectric+Mockito, `./gradlew testDevDebugUnitTest`) 신설 — 테스트_계획_2026-09-12.md
  B 참고. Flutter `integration_test/`도 같은 날 신설했으나 이 개발 환경(호스트
  총 RAM 6GB)에서 에뮬레이터+Gradle 빌드를 동시에 못 버텨 2026-09-13에 코드까지
  되돌림(실행 시도 2회 모두 메모리 부족으로 강제 종료) — 대신 에뮬레이터 기반
  수동/스크립트 탐색적 테스트(라운드 기반, 바탕화면 `테스트_진행상황.txt`)로
  커버함. `AlarmRefreshEngine.doRefresh()`/`computeDesiredAlarms()`와
  `ScheduleNotificationScheduler.triggerMillisFor()`를 테스트 가능하게 `private`→`internal`로
  넓힘(동작 변경 없음) - 새 Kotlin 테스트를 추가할 때 Robolectric이 아직 SDK 36을
  지원 안 해서 `android/app/src/test/resources/robolectric.properties`로 SDK 34에
  고정해둔 상태임을 참고할 것.
