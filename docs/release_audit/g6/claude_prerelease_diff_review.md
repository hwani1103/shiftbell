# 스토어 배포본 → dev 심층 비교 검토 (Claude)

- 기준: 스토어 `1.0.22+24` = `ca82d69`(태그 v1.0.22 = main) → dev 코드 `404c830`(`1.0.23+25`, 이후 커밋은 문서와 아래 R-03 수정뿐)
- 범위: 127커밋 / 218파일
  - 출시전 감사 수정(G0~G5)
  - 1.0.22 이후 만든 기능 전체(컨디션 매니저, 수면 기록·위젯, 백업/복원, 일정관리 탭·일정 알림, 카테고리 확장, Analytics, 광고)도 이번 업데이트로 한꺼번에 나감
- 초점: **1.0.22 사용자가 업데이트했을 때 기존 동작·데이터가 달라질 수 있는 지점**
- 방법: 코드 읽기, `git show`/`git diff`, APK `aapt dump badging` 비교. G0~G5 테스트 결과는 각 test_results 참고
- Codex의 병행 검토(별도 문서)는 읽지 않고 독립적으로 작성함
- **사용자 결정 반영(2026-09-14):** R-01은 안내 없이 수용, R-02는 배포 절차로 대응, R-03은 수정, R-04~R-07은 출시 체크리스트로 진행

## 요약

| # | 중요도 | 내용 | 결정 / 상태 |
|---|---|---|---|
| R-01 | Medium | 불규칙 근무 사용자가 1.0.22에서 개별 삭제·타입 변경한 알람(향후 10일)이 업데이트 직후 1회 원복됨 | **수용, 안내 안 함.** 1.0.23부터는 삭제·타입 변경이 `alarm_overrides`에 저장돼 재발 없음 |
| R-02 | Medium(절차) | prod 빌드에 광고 ID를 안 넣어도 빌드가 성공함 | **배포 절차로 대응 + 교차 검토 X-13으로 빌드 가드 추가(2026-09-15)** - 두 ID 중 하나라도 없거나 테스트 ID면 prod release 빌드 실패 |
| R-03 | Low | 스누즈 겹침 검사 날짜가 기기 기본 Locale을 따름 | **수정함**(`Locale.US`) |
| R-04 | 운영 | prod Analytics 수집이 새로 켜짐 | 출시 체크리스트: 데이터 보안 양식 갱신 |
| R-05 | 운영 | 광고 SDK가 AD_ID 등 일반 권한을 추가함 | 출시 체크리스트: 광고 ID·광고 포함 선언 |
| R-06 | 운영 | `latestVersionCode`를 단계적 출시 중에 올리면 받을 수 없는 사용자에게 안내가 뜸 | 출시 체크리스트: 100% 출시 뒤 25로 |
| R-07 | 운영 | prod AAB를 아직 한 번도 빌드 안 함 | 출시 체크리스트: 업로드 전 1회 빌드 |

## 1. 발견 사항

### R-01 Medium: 불규칙 근무 사용자의 개별 삭제·타입 변경 알람이 업데이트 직후 1회 원복됨
- **1.0.22 동작**
  - Native 갱신 엔진은 불규칙 근무에서 "기존 알람 재등록만" 했음(`ca82d69` AlarmRefreshEngine L110).
  - 알람 생성은 날짜에 근무를 배정할 때 Dart `regenerateFixedAlarms`만 했음.
  - 그래서 불규칙 사용자가 향후 10일 안의 알람을 개별 삭제하거나 타입을 바꾸면 그대로 유지됐음.
- **dev 동작(#26 P1, `REFRESH_POLICY_VERSION=1`)**
  - 업데이트 뒤 첫 트리거(MY_PACKAGE_REPLACED, 앱 실행, 자정)에서 강제 갱신이 1회 돌고, 불규칙 근무도 템플릿 기준으로 계산해 diff를 적용함.
  - `alarm_overrides`는 v24에서 새로 생긴 빈 테이블이라 1.0.22 시절의 삭제·변경 기록이 없음.
- **결과(불규칙 사용자, 향후 10일 창 안)**
  - 직접 삭제한 fixed 알람 → 다시 생성되어 울림
  - 타입을 바꾼 알람 → 템플릿 타입으로 돌아감
- 규칙 근무 사용자는 해당 없음. 1.0.22 엔진이 이미 매일 템플릿으로 되살렸음(#31 원래 버그).
- 의도된 개선도 같이 적용됨: 10일보다 앞서 배정해 두었는데 알람이 안 생기던 날짜에 이제 알람이 생김.
- **결정: 수용, 릴리스 노트 안내 없음.**
  - 1.0.22 상태를 예외로 역산하는 backfill은 넣지 않음. 틀리면 필요한 알람을 없애는 쪽으로 실패하기 때문.
- **앞으로의 보장(1.0.23 이후)**
  - 사용자 삭제는 `skip`, 타입 변경은 `set_type`으로 `alarm_overrides`에 저장됨.
  - 자동 갱신(Dart/Kotlin 공통 계산)은 예외를 적용한 뒤 diff하므로 원복되지 않음(#31, G1 테스트).
  - 이후 업데이트에서 `REFRESH_POLICY_VERSION`을 올려 강제 갱신이 다시 돌아도 예외는 유지됨.
  - 예외가 지워지는 경우는 해당 날짜의 배정이나 템플릿이 바뀔 때(D12), 그리고 슬롯이 30일 지났을 때(D11)뿐.
  - **정책 버전을 올리는 향후 변경에서 지킬 것:** 예외 적용을 우회하는 경로(예외 없이 전체 재생성)를 만들지 말 것.

### R-02 Medium(배포 절차): prod 빌드에 광고 ID를 안 넣어도 빌드가 성공함
- `ADMOB_BANNER_ID` dart-define이 없으면 배너 ID가 빈 문자열이 되고, 슬롯이 조용히 숨음(`banner_ad_slot.dart:51`). 수익 0.
- Gradle 속성 `ADMOB_APP_ID`가 없으면 Manifest 앱 ID가 Google 테스트 앱 ID로 대체됨(`build.gradle.kts:56-57`). 크래시는 없음.
- 이 PC에는 아직 `~/.gradle/gradle.properties`나 `android/gradle.properties`에 `ADMOB_APP_ID`가 없음.
- 1.0.22에는 광고가 없었으므로 회귀는 아님.
- **결정: 업데이트 빌드 전에 `업데이트_가이드.md` ③에 따라 두 값을 모두 주입.** 이후 교차 검토(X-13)에서 한쪽만 빠진 경우의 위험이 확인돼 `checkProdAdIds` 빌드 가드를 추가함(3.1절).
  - 배너 단위 ID: `--dart-define=ADMOB_BANNER_ID=…`
  - 앱 ID: `ADMOB_APP_ID`를 `~/.gradle/gradle.properties`에 넣거나 `-PADMOB_APP_ID=…`로 전달
  - 둘 중 하나만 넣으면 안 됨: 배너만 넣으면 테스트 앱 ID와 실제 배너가 섞이고, 앱 ID만 넣으면 광고가 안 뜸.

### R-03 Low: 스누즈 시각 겹침 검사가 기기 기본 Locale로 날짜를 만듦 → **수정함**
- 원인: `DatabaseHelper.isTimeConflict`가 `Locale.getDefault()`를 썼음. #17에서 DB 날짜 문자열을 `Locale.US`로 통일할 때 빠진 곳.
- 영향 범위
  - 호출처는 스누즈(`AlarmActionHelper.kt:143`) 하나.
  - ASCII 숫자가 아닌 Locale(아랍어 등)에서만 겹침 검사가 무력화됨.
  - 한국어·영어 사용자는 영향 없음.
  - 1.0.22에도 똑같이 있던 코드라 회귀는 아님.
- 수정: `DatabaseHelper.kt:305` → `java.util.Locale.US`. 표시용인 `AlarmGuardReceiver.kt:338`의 `HH:mm`은 DB 비교가 아니라서 그대로 둠.

### R-04 운영: Analytics가 prod 사용자에게 새로 켜짐
- `firebase_bootstrap.dart:43`에서 prod flavor는 수집 ON. 앱 내 개인정보 안내는 G5에서 갱신됨.
- **Play Console 데이터 보안 양식**(앱 활동·기기 ID 등)을 이번 업로드 전에 갱신할 것.

### R-05 운영: 광고 SDK가 권한을 새로 추가함
- 새 APK에 추가된 권한(aapt 비교): `com.google.android.gms.permission.AD_ID`, `ACCESS_ADSERVICES_AD_ID/ATTRIBUTION/TOPICS`, `BIND_GET_INSTALL_REFERRER_SERVICE`
- 모두 설치 시 자동 부여되는 권한이라 런타임 요청은 없음.
- Play Console에서 **"광고 ID" 선언을 "사용함"**, **"광고 포함"을 "예"**로 바꿔야 업로드가 거절되지 않음.

### R-06 운영: 업데이트 안내 원격값은 출시 완료 뒤에 올릴 것
- 1.0.22 앱도 Firestore `app_config.latestVersionCode`를 읽어 안내 팝업을 띄움(버전별 1회).
- 단계적 출시 중에 25로 올리면, 아직 받을 수 없는 사용자에게 안내가 뜨는데 스토어에는 업데이트 버튼이 없음. **100% 출시 후 25로 올릴 것.**

### R-07 운영: prod 번들은 아직 한 번도 빌드하지 않음
- 이번 기간에 빌드한 것은 dev release APK와 dev debug뿐.
- Kotlin 2.3.0, google-services 플러그인, 광고·Analytics 의존성이 추가됨.
- 업로드 전에 광고 ID(R-02)를 넣은 prod AAB를 한 번 빌드해 성공을 확인할 것.

## 2. 확인했고 문제없음(업데이트 회귀 없음)

| 영역 | 확인 내용 |
|---|---|
| OS 알람 예약 동일성 | 1.0.22의 CustomAlarmReceiver 예약·취소(MainActivity, AlarmRefreshEngine, AlarmGuardReceiver, AlarmActionHelper, DirectBootReceiver)는 전부 `data=shiftbell://alarm/<id>` + requestCode=id였음. 새 `AlarmWakeScheduler.baseIntent`와 filterEquals가 같아 새 예약이 옛 예약을 대체함(FLAG_UPDATE_CURRENT로 extras 갱신). DirectBoot의 `setPackage` 변형은 `cancelLegacyVariant`가 제거함 → 업데이트 후 이중 울림·유령 알람 없음 |
| 옛 예약의 늦은 도착 | 옛 Intent에는 `expectedAtMillis`가 없음 → 행이 있으면 울림(fail-open), 없으면 `SKIP_NO_ROW`. 1.0.22와 같음 |
| Guard 자정 wakeup | `Intent(AlarmGuardReceiver)` + requestCode 0, data 없음 → 1.0.22와 같은 PendingIntent |
| DB v18 → v24 | 스토어 DB는 v18. 19~24단계는 `ALTER ADD COLUMN … DEFAULT` / `CREATE … IF NOT EXISTS`뿐이고 파괴적 SQL 없음. G0의 v18 fixture는 `ca82d69` onCreate(L80-209)로 만들었고 Dart·Native 업그레이드 테스트 통과. MY_PACKAGE_REPLACED에서 Native가 먼저 열어도 직접 마이그레이션함 |
| 규칙 근무 강제 갱신 | diff 키에 `dayOffset`이 추가됐지만 기존 행과 템플릿이 모두 DEFAULT 0이라 키가 일치함 → 삭제·재생성 없음. fixed만 대상이고 custom·스누즈 알람은 건드리지 않음 |
| 권한/SDK | minSdk 24, targetSdk 36 동일. 새 런타임 권한 없음(R-05의 일반 권한만). 1.0.22 권한은 전부 유지 |
| 알림 채널 | `shiftbell_alarm_v3`, `shiftbell_result_v3` ID 불변 → 사용자 채널 설정 유지. 새 채널은 `shiftbell_restore`, `schedule_notify_v2` |
| SharedPreferences 키 | 1.0.22 키 중 삭제·이름 변경 없음. 새 키는 `schedule_tab_enabled`(기본 true)만 |
| 홈 화면 위젯 | `CalendarWidgetProvider`, `calendar_widget(_full)`, `calendar_widget_info` 유지 → 배치해 둔 위젯 그대로. 수면 위젯은 신규 |
| 백업 | MediaStore I/O에 Android 10 미만 가드(`MainActivity.kt:793,870`). 시작·재개·배경 전환 때 지문이 달라졌을 때만 실행 |
| 복원 잠금 | 업데이트 직후 `restore_state`가 없어 잠금 아님 → 알람 경로 막힘 없음 |
| 튜토리얼 팝업 | 1.0.22에 없던 플래그라 기존 사용자도 해당 탭을 처음 열 때 1회씩 봄(의도된 동작) |

## 3. 줄 단위로 보지 않은 부분(한계)
- 신규 기능 화면(컨디션, 수면, 일정관리)의 UI 세부. 기존 사용자도 빈 테이블에서 시작하는 새 기능이라 업데이트 회귀 경로가 아니라고 판단함.
- 울림 회차 토큰과 유지형 제어 알림(G1 #3/#4)의 경쟁 조건. T11 교차 검토와 Kotlin 테스트로 봤고, 이번에 다시 추적하지 않음. 실기기 테스트의 울림·스누즈·끄기 항목으로 확인.
- 친구 공유(G2)는 T13 테스트(F 40, FS 16) 결과를 신뢰함.

## 3.1 Codex 교차 검토(`codex_prerelease_diff_review.md`) 대조와 반영 (2026-09-15)

내 검토를 끝낸 뒤 Codex 문서를 읽고, 항목마다 404c830 코드로 다시 확인했다. 내 검토는 업데이트 경계(예약 동일성·DB·채널·키) 위주였고,
Codex는 G4 복원 경로의 UI·경합·완료 판정을 더 깊게 봐서 **내가 놓친 실제 결함이 여럿 있었다(X-02~X-09)**.

| Codex | 내 판단 | 조치 |
|---|---|---|
| X-01 기존 개별 변경 승계 누락 | 동의(내 R-01과 같음). 무음 변경도 원복됨 | **미수정 - 사용자 결정(안내 없이 수용, 1.0.23 이후 재발 방지로 충분)** |
| X-02 복원 중 탭 이동·재시작 생략 | 동의 | 설정 복원을 루트 네비게이터 전체 화면 `restore_progress_screen.dart`에서 실행(PopScope), 재시작을 화면 생명주기와 분리. 신규 설치 복원 화면도 진행 중 뒤로가기 차단 |
| X-03 복원 완료 재시작이 울림을 끊음 | 동의 | `app_restart.dart` - 이 프로세스에서 시작된 울림(`RingingAlarmTracker.isLiveRing`)이 끝날 때까지 기다린 뒤 재시작. 대기 안내 문구 |
| X-04 이월 경합 | 동의(스누즈 시각이 막 지나 수신 직전인 행이 교체로 지워지는 경로도 추가로 확인) | 네이티브 울림 상태 epoch + "종료 처리 중" ID. DB 교체 트랜잭션 끝에서 epoch 재비교 → 다르면 롤백·재시도(최대 5회). 이월 = 울림 + 종료 처리 중 + 최근 1시간 이후 스누즈. 스냅샷 저장 실패는 복원 실패. 스누즈가 사라진 행에 조용히 성공하지 않게 update 0건이면 롤백 |
| X-05 Guard 재등록이 잠금·DB 재확인 우회 | 동의 | `shouldDefer("guardRearm")` + `scheduleIfCurrent` |
| X-06 최종 재조정 실패를 성공 처리 | 동의 | 엔진 `refresh()`·일정 `rescheduleAllFromDb()`가 완료 여부 반환. 복원 재조정은 엔진 5회 재시도 후에도 미완료거나 일정 재예약 실패면 예외 → 미완료로 남김. 권한 거부 같은 개별 예약 실패는 재시도 목록으로 넘어가므로 미완료로 보지 않음. "지금 데이터로 계속"도 재조정 실패 시 작업 기록 유지 |
| X-07 직전 백업 삭제·후보 탐색 부족 | 동의 | 최신 + 직전 정상본 1개 보존(기억 URI 2개 + 스캔 시 1개 여유). 자동 탐지는 최신순 후보를 디코딩·근무표·스키마 검증까지 통과한 첫 파일로(최대 5개) |
| X-08 백업에 없는 설정 키가 남음 | 동의 | 복원 대상 키 중 백업에 없는 키는 삭제(친구공유·설치별 키는 그대로) |
| X-09 설정 자료형·날짜 형식 검증 | 동의(손상·편집 파일 edge) | `kBackupPreferenceTypes` 등록표로 키별 자료형 검증, 알람 date·예외 slot_time 저장 형식 검증, 탭 설정·재조정의 읽기를 자료형 방어 |
| X-10 제어 알림 채널 변경 | 부분 동의(드묾) | 새 알람 채널이 차단돼 있고 옛 `alarm_control` 채널이 허용돼 있으면 옛 채널로 게시. 옛 채널 차단 설정이 새 알림에 적용 안 되는 점은 알람 신뢰성 의도(#4)대로 유지 |
| X-11 80자 초과 공유 이름 | 동의 | 거부 대신 80자로 잘라 표시·업로드, 입력칸 maxLength. G2 테스트 F-D03·F-P05를 새 동작으로 갱신 |
| X-12 회차 없는 옛 제어 Intent | 동의 | 활성 울림이 옛 버전 기록(LEGACY_ROUND)이고 ID가 같을 때만 매핑(`normalizeRound`). 새 회차에는 매핑 안 함 |
| X-13 광고 ID 한쪽 누락 | 동의 - **내 R-02 설명("빠뜨리면 광고만 안 뜬다")과 메모장 설명이 틀렸음** | prod release 빌드 전 `checkProdAdIds`: 두 ID 중 하나라도 없거나 테스트 ID면 빌드 실패. 실패/통과 둘 다 확인함 |
| X-14 dev 초기 Analytics 수집 | 동의 | Manifest `firebase_analytics_collection_enabled` placeholder(dev false / prod true) |
| 추가 edge: `assigned_dates` 손상 → 불규칙 미래 알람 전부 삭제 | 동의 | 파싱 실패를 빈 배정으로 바꾸지 않고 갱신 실패(롤백)로 |

남은 한계(코드로 못 막은 것):
- 복원 DB 교체 트랜잭션이 잠금을 쥔 몇 초 동안 네이티브 스누즈 DB 쓰기가 SQLite busy로 실패하면 그 스누즈는 사라질 수 있음(1.0.22에는 복원 자체가 없음, 매우 짧은 창)
- 복원 확인 직전에 이미 진행 중이던 Dart 쓰기 조정은 하지 않음(전용 화면 진입 뒤에는 UI 쓰기 불가)
- Codex 메모장 권고 중 "내부 테스트 트랙" 사용은 사용자 방침(본인 기기만)대로 넣지 않음. 사실 오류(8889 30초 자동 삭제, 진동 테스트 지속시간, 광고 ID 설명, 복원 후 시각 수정 금지)는 고치고 테스트 8(덮어쓰기 복원 이동 차단·울리는 중 복원) 추가

검증: `flutter analyze` 변경 파일 신규 경고 0 · Dart 전체 259/259(신규 g6 7 포함) · Kotlin `testDevDebugUnitTest` 75/75(신규 G6CrossReviewTest 4 포함) · `checkProdAdIds` 누락 시 실패/주입 시 통과

## 4. 출시 체크리스트
1. 실기기 필수 테스트(바탕화면 메모장)
2. 광고 ID 두 값(배너 dart-define + `ADMOB_APP_ID`)을 넣고 prod AAB 빌드(R-02, R-07)
3. Play Console: 데이터 보안(R-04), 광고 ID·광고 포함 선언(R-05)
4. 단계적 출시 → 100% 뒤 `latestVersionCode=25`(R-06)
