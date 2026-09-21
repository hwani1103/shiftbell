# 1.0.23+25 출시 인수인계 (2026-09-21)

다음 세션은 **"3. 출시 절차"의 미완료 항목**부터 이어서 하면 된다. 코드 작업은 사실상 끝났고, 남은 건 커밋·광고 ID·배포·Firebase 값 변경이다.

## 1. 현재 상태 (2026-09-21 기준, 직접 확인한 값)

- 브랜치 `dev`, HEAD `636c215`. 버전 `pubspec.yaml` `1.0.23+25` = `build.gradle.kts` `versionCode 25 / "1.0.23"` (일치).
- 운영 중인 버전은 `v1.0.22`(태그·`main`). 이번 릴리스는 아직 `main`에 병합·태그 안 됨.
- **커밋 안 된 변경이 약 48개** — 아래 두 덩어리가 섞여 있다. 사용자가 아직 커밋을 요청하지 않아 건드리지 않았다.
  - (a) 이번 세션 작업: 수면·회복 탭 v4(개인 기준선)·근무별 평균 수면·일괄 확인, 브리핑 문구 다듬기, 수면 위젯 레이아웃, 1회성 팝업 문구 갱신, 릴리즈 노트 팝업 끄기, CLAUDE.md 갱신.
    (`636c215`에는 v3 재설계까지만 들어 있음)
  - (b) 이전부터 쌓인 G6 재검토 작업: `AlarmOverlayService.kt`·`AlarmPlayer.kt`·`CustomAlarmReceiver.kt`·`MainActivity.kt`·`RingingAlarmTracker.kt`, 온보딩/백업/설정/달력 화면, `layout_limits.dart`·`blocking_progress.dart`·`current_date_provider.dart`·`AlarmStreamVolume.kt` 등 신규 파일, `docs/release_audit/g6/recheck_2026_09_15/`. 이 세션에서 내용을 다시 검토하지 않았다.
- 검증 결과: `flutter test` 266개 통과, `flutter analyze`는 `web_main.dart`의 기존 error 1건 외 새 문제 없음, Kotlin `testDevDebugUnitTest` 통과(위젯 변경 직후), `flutter build apk --debug --flavor dev` 성공(위젯 변경 직후).
  팝업/릴리즈 노트 수정 뒤에는 Dart 테스트·분석만 다시 돌렸고 APK 빌드는 안 했다(Dart 문구 변경이라 위험은 낮음).
- 폰에는 **최신 빌드가 설치되지 않았다**(빌드 도중 USB 연결이 끊김). 폰 연결 후 `flutter install --debug --flavor dev`.

## 2. 이번 세션에서 확정한 결정 (다시 묻지 말 것)

- 수면·회복 탭 개인 기준선(`baselineWeeklyMinutesAsOf`): "평소"는 스케줄 패턴 자체의 평균이고 OT·일회성 근무변경은 반영하지 않는다(이대로 유지 — 사용자 확인). 몇 주 연속 OT가 붙는 경우도 매주 신호가 뜨는 게 맞는 동작.
- 수면 귀속 로직(어제 휴무·오늘 야간·내일 휴무)은 실제 테스트로 검증해 정상 — 수정 안 함.
- 수면 위젯: 프레임 `150x110dp(3x2)`는 그대로 두고(줄이면 런처마다 1행/2행으로 다르게 잡히던 과거 버그 재발), "상태" 줄을 없애고 근무명 칩 + 수면/기상 버튼 두 요소만 크게 키움. Robolectric NATIVE 렌더로 근무명 2/4/10자 모두 확인.
- **"이번 업데이트는 꼭 확인해주세요" 팝업 제거**: `update_service.dart`의 `_releaseNoteVersion = ''`(기존에 설계돼 있던 끄는 방법). "새 버전이 있어요!" 안내는 유지.
- 1회성 팝업은 정확히 4개(`onboarding_info_popups.dart`): 웰컴 / 불규칙 근무 배정 안내 / 일정관리 탭 / 수면·회복 탭. 이번에 웰컴의 "수면·컨디션 관리"를 "수면·회복 관리"로, 수면·회복 탭 안내를 전면 갱신(라벨 "최근 근무·수면", 근무별 평균 수면, 일괄 확인, 중복 "3." 번호 정리). 불규칙·일정관리 안내는 실제 동작과 일치해 그대로. 이 4개 외 1회성 안내 팝업은 없다(업데이트 안내 다이얼로그 제외).

## 3. 출시 절차 (미완료 — 이 순서로)

### 3-1. 커밋 (사용자 확인 필요)
- 위 (a)와 (b)를 한 번에 커밋할지 나눌지 사용자에게 먼저 묻는다. 이전 커밋들이 여러 주제를 한 커밋에 묶는 관례이긴 하다.
- (b)는 이 세션에서 검토하지 않았으니, 커밋 전에 `git diff --stat`으로 범위를 다시 보여주고 확인받을 것.
- 커밋 메시지 끝에 Co-Authored-By 줄(시스템 지침 참고).

### 3-2. 실제 AdMob ID 주입 — 사용자가 직접 할 일 vs Claude가 할 일
현재 이 PC에는 `ADMOB_APP_ID`가 **설정돼 있지 않다**(`~/.gradle/gradle.properties`에 없음). `android/key.properties`(서명 키)는 있음.
`checkProdAdIds`(build.gradle.kts)가 두 ID 중 하나라도 없거나 구글 테스트 ID면 prod release 빌드를 **실패시킨다** — 그래서 빠뜨려도 조용히 나가지 않는다.

**사용자가 할 일 (Claude가 대신 못 함 — AdMob 콘솔 로그인 필요)**
1. AdMob 콘솔에서 이 앱(패키지 `com.hwani1103.shiftbell`)의 **앱 ID**(`ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY`)와 **배너 광고 단위 ID**(`ca-app-pub-XXXXXXXXXXXXXXXX/ZZZZZZZZZZ`)를 확인한다. 광고 단위 형식이 "배너"인지 확인. dev 패키지(`.dev`)에는 실제 ID를 쓰지 않는다.
2. 앱 ID를 `C:\Users\Administrator\.gradle\gradle.properties`에 한 줄 추가(파일이 없으면 만들기): `ADMOB_APP_ID=ca-app-pub-XXXX~YYYY`. 저장소 안에 넣지 말 것.
3. 배너 광고 단위 ID는 아래 빌드 명령에 붙인다(소스에 안 넣음). 두 ID를 Claude에게 알려주면 빌드 명령 실행은 Claude가 할 수 있다(ID는 비밀 키는 아니지만 커밋하지 말 것).
4. (확인 권장, 이 세션에서 검증 못 함) Play Console → 앱 콘텐츠에서 **광고 ID 사용 선언**, **데이터 보안(Data safety)** 양식에 광고·Analytics 수집이 맞게 적혀 있는지. AdMob 앱이 Play 스토어 등록과 연결됐는지도 콘솔에서 확인.

**Claude가 할 일**
```bash
flutter build appbundle --release --flavor prod --dart-define=ADMOB_BANNER_ID=<배너 단위 ID>
```
- 산출물: `build/app/outputs/bundle/prodRelease/app-prod-release.aab` (`key.properties`로 서명).
- 빌드 뒤 확인: 실패 메시지 `prod release 광고 ID 확인 실패`가 없어야 하고, 가능하면 내부 테스트 설치본에서 광고 영역에 **파란 틴트/"Test Ad" 표시가 없는지** 사용자가 확인.
- 빌드는 메모리를 많이 쓴다 — 이 세션에서 백그라운드 빌드가 메모리 부족으로 한 번 강제 종료됐다. 다른 무거운 작업 없이 하나만 돌릴 것(전에 `gradlew --stop`).

### 3-3. Play Console
- 내부 테스트 트랙에 aab 업로드 → 설치·광고·알람 동작 확인 → 프로덕션 출시. (스토어 "이번 버전 새로운 기능" 문구는 Play Console에 입력하는 것이고 앱 안 팝업과 무관.)
- 실기기 절차 문서(바탕화면 `교대시계_출시전_필수_실기기테스트.txt`, `교대시계_실기기테스트_폰단독.txt`)는 사용자가 이미 마쳤다고 함. 단 **수면 위젯은 이번에 크기를 바꿨으니 실기기에서 한 번 더 봐야 한다**(코드상 3x2 프레임 그대로라 위험은 낮음).

### 3-4. Git 병합·태그 (CLAUDE.md 릴리스 규칙)
dev → `main` 병합 → `git tag -a v1.0.23` → push(태그 포함). push는 사용자 확인 후.

### 3-5. Firebase `latestVersionCode` (사용자 몫 — 콘솔에서 직접)
- 앱은 Firestore 문서 `app_config/android`의 `latestVersionCode`(숫자)를 읽어 설치된 버전코드보다 크면 "새 버전이 있어요!"를 한 번 띄운다(`update_service.dart`, 쿨다운 6시간, 버전당 1번).
- **`25`로 올리면 된다.** 단 **Play에서 실제로 배포가 퍼진 뒤에** 올릴 것 — 먼저 올리면 사용자가 스토어를 열어도 업데이트가 아직 안 보이는 상태가 된다(단계적 출시라면 출시 비율 밖 사용자도 안내를 받는 점 감안).
- 강제 업데이트 필드(`minSupportedVersionCode` 등)는 코드에서 제거돼 넣어도 무시된다.
- 그래서 "배포 후 Firebase에서 versionCode 올리면 끝?" → 인앱 업데이트 안내 측면에서는 **맞다**. 위 3-1~3-4가 그 앞에 필요할 뿐이다.

### 3-6. 배포 후 문서 정리
- CLAUDE.md 맨 위 "현재 운영 버전"을 `v1.0.23+25`로, 태그·main 커밋 해시 갱신.
- `_releaseNoteVersion`이 빈 문자열인 상태로 나가므로, 다음에 릴리즈 노트를 쓰려면 그 버전 문자열로 바꾸고 `updateReleaseNoteTitle/Body`(ko·en ARB)를 새로 쓴다. (새로 설치한 사용자의 기준선 값이 `''`로 저장되므로, 나중에 노트를 켜면 그 사용자들도 한 번 보게 된다 — 감안.)

## 4. 알려진 잔여 사항 (출시를 막지는 않음)

- 1회성 팝업은 평생 1회 플래그(`condition_tab_tutorial_shown` 등)라, 이미 예전 수면·회복 탭 안내를 본 사용자는 갱신된 안내를 다시 못 본다. 다시 보여주려면 그 키 이름을 `_v2`로 바꾸면 된다(필요하면 결정).
- 수면·회복 탭 임계값(15%/25%/6h/12h, 연속근무 7·10일)은 논문 수치가 아니라 앱 판단 — 실사용 피드백으로 튜닝 여지. CLAUDE.md "설계 기록 › 컨디션 매니저" 참고.
- 미검증(실기기): 홈 위젯 표시(이번 크기 변경 포함), G4 백업·복원 실제 실행, prod release 광고·Analytics 목적지.
- AUD-04(백그라운드 울림 지속, foreground service 없음)는 코드 미수정 — 실기기 테스트 결과를 사용자가 확인했는지 재확인.
