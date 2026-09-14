# 스토어 배포본 → dev 심층 비교 검토 (Claude)

- 기준: 스토어 `1.0.22+24` = `ca82d69` (태그 v1.0.22 = main) → dev 코드 `404c830` (`1.0.23+25`, 이후 커밋은 문서만)
- 범위: 127커밋 / 218파일. 출시전 감사 수정(G0~G5)뿐 아니라 1.0.22 이후 만든 기능 전체(컨디션 매니저, 수면 기록·위젯, 백업/복원, 일정관리 탭·일정 알림, 카테고리 확장, Analytics, 광고)가 이번 업데이트로 한꺼번에 나감
- 초점: **1.0.22 사용자가 업데이트했을 때 기존 동작·데이터가 달라질 수 있는 지점**
- 방법: 코드 읽기와 `git show`/`git diff`, APK `aapt dump badging` 비교. 새 빌드나 테스트는 돌리지 않음(G0~G5 테스트 결과는 각 test_results 참고)
- Codex의 병행 검토 파일(`prerelease_diff_review.md`)은 읽지 않은 상태에서 독립적으로 작성함

## 1. 발견 사항

### R-01 Medium: 불규칙 근무 사용자는 업데이트 직후 직접 지운 알람이 되살아날 수 있음(1회)
- 1.0.22:
  - Native 갱신 엔진은 불규칙 근무에서 "기존 알람 재등록만" 했음(`ca82d69` AlarmRefreshEngine L110).
  - 알람 생성은 날짜에 근무를 배정할 때 Dart `regenerateFixedAlarms`만 담당했음.
  - 그래서 불규칙 사용자가 앞으로 10일 안의 알람을 개별 삭제하거나 타입을 바꾸면 그대로 유지됐음.
- dev(#26 P1, `REFRESH_POLICY_VERSION=1`):
  - 업데이트 뒤 첫 트리거(MY_PACKAGE_REPLACED, 앱 실행, 자정)에서 강제 갱신이 1회 돌고, 불규칙도 템플릿 기준으로 계산한 뒤 diff를 적용함.
  - 개별 예외(`alarm_overrides`)는 v24에서 새로 생긴 빈 테이블이라, 1.0.22 시절의 삭제·타입 변경 기록이 없음(되살리는 backfill 없음).
- 결과(불규칙 사용자, 앞으로 10일 창 안):
  - 직접 삭제한 fixed 알람 → 다시 생성되어 **울림**
  - 타입을 바꾼 알람 → `superseded`로 교체되어 템플릿 타입으로 돌아감
- 규칙 근무 사용자는 해당 없음. 1.0.22 엔진이 이미 매일 템플릿으로 되살렸음(그게 #31 원래 버그).
- 의도된 개선도 함께 적용됨: 10일보다 앞서 배정해 두고 알람이 안 생기던 날짜에 이제 알람이 생김.
- 판단: 코드로 막으려면 "1.0.22 상태를 예외로 역산하는 1회 backfill"이 필요함. 생성 이력과 삭제 이력을 대조해야 해서 복잡하고, 틀리면 필요한 알람을 없애는 쪽으로 실패함. **코드 수정 없이 릴리스 노트로 안내하는 것을 권장**함.
  - 문구 예: "불규칙 근무표 알람 자동 생성이 개선되어, 업데이트 직후 한 번 앞으로 10일 알람이 템플릿 기준으로 다시 정리됩니다."

### R-02 Medium(배포 절차): prod 빌드에 광고 ID를 안 넣어도 빌드가 성공함
- `ADMOB_BANNER_ID` dart-define이 없으면 배너 ID는 빈 문자열이고, 슬롯이 조용히 숨음(`banner_ad_slot.dart:51`). 수익 0.
- Gradle 속성 `ADMOB_APP_ID`가 없으면 AndroidManifest의 앱 ID가 **Google 테스트 앱 ID로 대체**됨(`build.gradle.kts:56-57`). 크래시는 없지만 운영 앱에 테스트 앱 ID가 박힘.
- 현재 이 PC에는 `~/.gradle/gradle.properties`가 없고, `android/gradle.properties`에도 `ADMOB_APP_ID`가 없음.
- 1.0.22에는 광고 자체가 없었으므로 **회귀는 아님**. 배포 실수 방지 문제임.
- 권장: prod release 빌드에서 둘 중 하나라도 비면 빌드를 실패시키는 가드 추가(수 줄). 아니면 `업데이트_가이드.md` ③단계를 반드시 따를 것.

### R-03 Low: 스누즈 시각 겹침 검사가 기기 기본 Locale로 날짜를 만듦
- `DatabaseHelper.isTimeConflict`(`DatabaseHelper.kt:303-306`)는 아직 `Locale.getDefault()`임. #17에서 DB 날짜 문자열을 `Locale.US`로 통일할 때 빠진 곳.
- 호출처는 스누즈(`AlarmActionHelper.kt:143`) 한 곳뿐.
- 아랍어처럼 숫자가 ASCII가 아닌 Locale에서만 비교가 틀어짐. 결과는 겹침 검사가 무력화되는 정도라, 스누즈 알람이 다른 알람과 같은 시각에 설 수 있음.
- 한국어·영어 사용자에게는 영향 없음. 다음 버전에서 `Locale.US`로 한 줄 수정 권장.
- 1.0.22(`ca82d69` DatabaseHelper L206-208)에도 똑같이 있던 코드라 **이번 업데이트의 회귀는 아님**.

### R-04 운영: Analytics가 prod 사용자에게 새로 켜짐
- `firebase_bootstrap.dart:43`은 prod flavor에서 수집 ON.
- 앱 안의 개인정보 안내는 G5에서 갱신됨.
- **Play Console 데이터 보안 양식**(앱 활동·기기 ID 수집 여부)을 이번 업로드 전에 갱신해야 함.

### R-05 운영: 광고 SDK가 권한을 새로 추가함
- 새 APK에 `com.google.android.gms.permission.AD_ID`, `ACCESS_ADSERVICES_AD_ID/ATTRIBUTION/TOPICS`, `BIND_GET_INSTALL_REFERRER_SERVICE`가 들어옴(aapt 비교).
- 모두 설치 시 자동 부여되는 권한이라 런타임 권한 요청은 없음.
- Play Console **"광고 ID" 선언**을 "사용함"으로, **"광고 포함"**을 "예"로 바꿔야 업로드가 거절되지 않음.

### R-06 운영: 업데이트 안내 원격값은 출시 완료 뒤에 올릴 것
- 1.0.22 앱도 Firestore `app_config.latestVersionCode`를 읽어 안내 팝업을 띄움(버전별 1회).
- 단계적 출시 중에 25로 올리면, 아직 업데이트를 못 받는 사용자에게 "업데이트하세요"가 떠도 스토어에 버튼이 안 보임.
- **100% 출시 후에 올릴 것.**

### R-07 운영: prod 번들은 아직 한 번도 빌드하지 않음
- 이번 기간에 빌드한 것은 dev release APK와 dev debug뿐임.
- Kotlin 2.3.0, google-services 플러그인, 광고·Analytics 의존성이 추가된 상태임.
- 업로드 전에 `flutter build appbundle --release --flavor prod --dart-define=ADMOB_BANNER_ID=…` + `-PADMOB_APP_ID`(또는 gradle.properties)로 한 번 빌드해 성공을 확인해야 함.

## 2. 확인했고 문제없음(업데이트 회귀 없음)

| 영역 | 확인 내용 |
|---|---|
| OS 알람 예약 동일성 | 1.0.22의 CustomAlarmReceiver 예약·취소(MainActivity, AlarmRefreshEngine, AlarmGuardReceiver, AlarmActionHelper, DirectBootReceiver)는 전부 `data=shiftbell://alarm/<id>` + requestCode=id였음. 새 `AlarmWakeScheduler.baseIntent`와 filterEquals가 같으므로 새 예약이 옛 예약을 **대체**함(FLAG_UPDATE_CURRENT로 extras 갱신). DirectBoot의 `setPackage` 변형은 `cancelLegacyVariant`가 제거함. → 업데이트 후 이중 울림이나 유령 알람 없음 |
| 옛 예약이 늦게 도착 | 옛 Intent에는 `expectedAtMillis`가 없음. 행이 있으면 울리고(fail-open), 행이 없으면 `SKIP_NO_ROW` → 1.0.22와 같은 동작 |
| Guard 자정 wakeup | `Intent(AlarmGuardReceiver)` + requestCode 0, data 없음 → 1.0.22와 같은 PendingIntent |
| DB v18 → v24 | 스토어 DB는 **v18**. 19~24단계는 `ALTER ADD COLUMN … DEFAULT` / `CREATE … IF NOT EXISTS`만 있고 파괴적 SQL은 없음. G0의 v18 fixture는 `ca82d69` onCreate(L80-209)로 만들었고 Dart·Native 업그레이드 테스트 통과. MY_PACKAGE_REPLACED에서 Native가 먼저 열어도 Native가 직접 마이그레이션함 |
| 규칙 근무 강제 갱신 | diff 키에 `dayOffset`이 추가됨. 기존 행과 템플릿이 모두 DEFAULT 0이라 키가 일치하므로 규칙 사용자 알람은 삭제·재생성되지 않음. fixed만 대상이고 custom·스누즈 중 알람은 건드리지 않음 |
| 권한/SDK | minSdk 24, targetSdk 36 동일. 새 런타임 권한 없음(R-05의 일반 권한만 추가). 1.0.22의 권한 목록은 모두 유지됨 |
| 알림 채널 | 알람 `shiftbell_alarm_v3`, 결과 `shiftbell_result_v3` ID 불변 → 사용자가 바꾼 채널 설정 유지. 새 채널은 `shiftbell_restore`, `schedule_notify_v2`뿐 |
| SharedPreferences 키 | 1.0.22 키 중 삭제·이름 변경된 것 없음. 새 키는 `schedule_tab_enabled`(기본 true)만 있음 |
| 홈 화면 위젯 | `CalendarWidgetProvider`, `calendar_widget(_full)`, `calendar_widget_info` 이름 유지 → 이미 배치한 위젯 그대로. 수면 위젯은 신규 |
| 백업 | MediaStore 쓰기·읽기에 Android 10 미만 가드 있음(`MainActivity.kt:793,870`). 앱이 백그라운드로 갈 때만 실행 |
| 복원 잠금 | 업데이트 직후 `restore_state`가 없어 잠금 아님 → 알람 경로가 막히지 않음 |
| 튜토리얼 팝업 | 1.0.22에는 없던 플래그라, 기존 사용자도 해당 탭을 처음 열 때 1회씩 보게 됨(의도된 동작) |

## 3. 이번 검토에서 줄 단위로 보지 않은 부분(한계)
- 신규 기능 화면(컨디션, 수면, 일정관리 탭)의 UI 세부. 기존 사용자에게는 빈 테이블에서 시작하는 새 기능이라 업데이트 회귀 경로가 아니라고 판단함.
- 알람 울림 회차 토큰·유지형 제어 알림(G1 #3/#4)의 경쟁 조건은 T11 교차 검토와 Kotlin 테스트로 봤고, 이번에 다시 추적하지 않음. 바탕화면 실기기 테스트 목록의 울림·스누즈·끄기 항목으로 확인 필요.
- 친구 공유(G2)는 T13 테스트(F 40, FS 16) 결과를 신뢰함.

## 4. 출시 전 권장 순서
1. (선택, 권장) R-02 prod 광고 ID 빌드 가드
2. 실기기 필수 테스트(바탕화면 메모장). **불규칙 근무 사용자라면 R-01 확인 항목을 추가**: 1.0.22에서 개별 알람 하나를 지운 뒤 업데이트하고, 되살아나는지 확인
3. prod AAB 빌드(R-07)
4. Play Console: 데이터 보안(R-04), 광고 ID·광고 포함 선언(R-05), 릴리스 노트(R-01 문구)
5. 단계적 출시 → 100% 뒤 `latestVersionCode=25`(R-06)
