# T04 — S1 실기기 확인 절차 (사용자)

작성: Claude, 2026-09-14. 대상: G0 제품 코드 `release/g0` `637b56a` 이후. 결과는 `g0/test_results.md` 5장 S1 행에 적는다.

## 왜 필요한가

자동 테스트로는 "업데이트 후 앱을 한 번도 안 연 상태", "재부팅 후 첫 잠금 해제 전", "release APK 안의 SQL 원본을 네이티브가 읽는지"를 확인할 수 없다. G0(#1) 수정의 핵심이 바로 이 경로라서 실기기가 필수다.

## 안전 원칙

- **반드시 dev flavor(`com.hwani1103.shiftbell.dev`)로만 한다.** 스토어 설치본(`com.hwani1103.shiftbell`)과 완전히 다른 앱이라 건드리지 않는다.
- flavor 없이 `flutter install`/`run` 금지(스토어 앱이 삭제될 수 있음 — CLAUDE.md).
- ADB 명령은 항상 `-s <기기 시리얼>`로 대상을 지정한다. `adb devices`로 시리얼 확인.
- 옛 버전(`v1.0.22`)과 새 버전을 **같은 PC의 같은 서명키**로 빌드해야 덮어 설치(`install -r`)가 된다. 서명 오류가 나면 기존 앱을 지워서 우회하지 말 것(그러면 업데이트 검증이 아님).

## 준비 (한 번)

1. 옛 버전 빌드용 폴더 만들기 (PowerShell 또는 Git Bash, 메인 폴더에서):
   ```
   git worktree add ..\shiftbell-v1022 v1.0.22
   ```
2. 메인 폴더에서 추적 제외 파일 복사: `android\key.properties`, `android\local.properties`, `android\gradlew`, `android\gradlew.bat`, `android\gradle\wrapper\gradle-wrapper.jar` → `shiftbell-v1022\android\` 같은 위치. (`key.properties`가 가리키는 keystore 경로가 상대경로면 그 파일도 같은 상대 위치에 있어야 함)
3. 새 버전 폴더 `shiftbell-g0`에도 `android\key.properties`가 없으면 같은 방식으로 복사.
4. 기기: 개발자 옵션 → USB 디버깅, 알림·정확한 알람·다른 앱 위에 표시 권한 허용 준비.

## 케이스 ① 업데이트 후 앱을 열지 않고 알람 울림

1. 기기에 dev 앱이 이미 있으면 **설정 → 앱 → 교대시계 (테스트) → 저장공간 삭제**로 초기화(dev 앱만).
2. 옛 버전 설치:
   ```
   cd ..\shiftbell-v1022
   flutter install --release --flavor dev -d <시리얼>
   ```
3. 옛 앱을 열어 온보딩·근무표 설정, **지금부터 15~20분 뒤에 울리는 알람**이 생기게 템플릿 또는 개별 알람 추가. 알람 타입을 소리로. 앱을 완전히 닫는다(최근 앱에서 스와이프).
4. 새 버전 빌드 후 **덮어 설치만** 하고 앱은 열지 않는다:
   ```
   cd ..\shiftbell-g0
   flutter build apk --release --flavor dev
   adb -s <시리얼> install -r build\app\outputs\flutter-apk\app-dev-release.apk
   ```
5. 로그를 켜 둔다:
   ```
   adb -s <시리얼> logcat -s DatabaseHelper DbMigrationRunner CustomAlarmReceiver AlarmPlayer
   ```
6. 알람 시각까지 기다린다. 기록할 것:
   - 알람이 **설정한 소리/진동**으로 울렸는가 (진동만 울리면 실패 — 예전 증상)
   - 스누즈 → 5분 뒤 다시 울리는가, 끄기 동작
   - 로그에 `🔧 Native 마이그레이션 시작 v18 → v24`와 `✅ Native 마이그레이션 완료`가 있는가
   - 로그에 `❌ SQL 원본을 못 읽어` 또는 `DbMigrationException`이 **없는가** (release APK 자산 읽기 확인)
7. 그 뒤 앱을 열어 근무표·메모·알람 이력이 그대로인지, 시작 실패 화면이 안 뜨는지 확인.

## 케이스 ② 재부팅 후 첫 잠금 해제 전 알람

1. 케이스 ①의 1~4를 다시 한다 (알람은 재부팅 시간을 고려해 20~30분 뒤로).
2. 새 버전 덮어 설치 후 앱을 열지 않고 **기기 재부팅**. 재부팅 후 **잠금을 풀지 않는다.**
3. 알람 시각까지 잠금 화면 상태로 대기 → 울리는지, 소리·스누즈·끄기.
4. 이후 잠금 해제하고 PC에 연결해 `adb -s <시리얼> logcat -d -s DatabaseHelper DbMigrationRunner DirectBoot > s1_case2.log`로 부팅 직후 마이그레이션 로그 확보(버퍼가 남아 있으면).

## 케이스 ③~⑤ (가능하면)

- ③ 10일 창: 케이스 ① 이후 앱의 다음 알람/달력에서 오늘~+9일 알람이 채워져 있는지.
- ④ 동시 open: 알람이 울리는 순간 앱 아이콘을 눌러 열기 → 앱이 정상 시작, 알람 정상 종료.
- ⑤ 수면 위젯: 홈 화면 수면 위젯이 새 버전 설치 후 앱을 열기 전에도 상태를 표시하는지.

## 기록 양식 (test_results.md 5장에 붙여 넣기)

```
S1 실기기 — 일시:
기기 모델 / Android 버전 / 시리얼 끝 4자리:
옛 버전 커밋 d7363ba (v1.0.22) / 새 버전 커밋:
케이스 ① 결과(PASS/FAIL) + 소리·스누즈·끄기 + 로그 핵심 줄:
케이스 ② 결과 + 잠금 해제 전 울림 여부:
케이스 ③④⑤ 결과 또는 NOT_RUN:
특이사항:
```

개인정보(실제 근무표·메모 내용)는 기록하지 않는다.
