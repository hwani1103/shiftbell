# Sync Path Lab DEV — 0.9.0+11 / 100 levels

현행은 100레벨에서 끝나는 캠페인이다. 1~70의 맵/판정/저장 identity를 보존하고, 71~100에 필수 이동 한도6→14인 협동 퍼즐을 추가한다. 100은8×8, 나머지 신규 레벨은7×7이다. 문2개/포탈2쌍 이내의 기존 장치만 사용한다.

시작 시 공 선택 없음, 자동 다음 공 선택 없음. 공/장치의 문자·번호 대신 색·무늬·경유지 깃발과 열쇠/문을 사용한다. 제목은 없애고 LV만 표시한다. 마지막 LV의 파란 테두리와 목록 위치를 복원한다.

기본은 순차 해금이다. 목록 상단 잠금 아이콘은 전체 레벨+무한 하트를 임시로 켠다. 레벨별3하트는 함께 출발에서 차감하며, 모두 소진한 뒤 앱 안60초/개·앱 밖3600초/개로3개까지 충전한다. 저장 키는 `syncPathLab.dev.v6.campaign50gates.progress`를 유지한다.

검사와 독립 dev debug APK/웹 빌드: `tools/check_finale100_lab.ps1 -Build`. 최종 결과·제약·해답·증거는 `docs/next_version_27이후/game_implementation_v11/00_구현검증_읽기순서.txt`를 따른다. release/기기 설치/ShiftBell dev·prod 통합은 수행하지 않는다.

아래는 이전 버전 기록이다.

# Sync Path Lab DEV — 0.7.0+9

현행50레벨은 시간제 스위치·문 포함. UI를 레벨/메뉴·보드·공별 남은 횟수·출발로 간소화했다.
실패 시 다시 시작/종료. 경로 수정·도움말·힌트는 메뉴에 있다. 슬라이더/다시보기 제거.
처음 기본 규칙 및 문 규칙을 안내하고 확인 여부를 저장한다. 기존 게임 진행 키는 유지한다.
검사/독립 DEV 빌드: `tools/check_compact50_lab.ps1 -Build`.
증거: `docs/next_version_27이후/game_implementation_v9/`.

아래는 이전 버전 기록이다.

# Sync Path Lab DEV — source 0.6.0+8

현행 소스는 50레벨이다. 1–30 유지, 31–50에 시간제 스위치·문 추가.
31–33:2공/문1개, 34–41:3공/문1개, 42–50:4공/문2개.
Goal은 노란 별, 공은 약11% 확대. 기존 일정한 칸당 속도와1.5배 재생 유지.
저장 키: `syncPathLab.dev.v6.campaign50gates.progress` (이전 기록 보존).
검증만: `tools/check_gates50.ps1`. APK/웹 빌드는 사용자 요청으로 실행하지 않았다.
현재 APK는 이전30레벨0.5.0+7이다. 현재 소스 APK로 오인하지 말 것.
설계/검증: `docs/next_version_27이후/game_implementation_v8/`.

아래는 이전 버전의 기록이며 설치 명령은 재빌드 전에는 이전 APK를 설치한다.

# Sync Path Lab DEV — prototype 0.5.0+7

현행은 50개에서 선별한 30레벨이다. 1–3 튜토리얼 이후 빠르게 난이도가 올라간다.
2공은1–6, 3공은7–15, 4공은16–30. 기존50의 마지막 문제를 유지한다.
새 저장 키: `syncPathLab.dev.v5.campaign30condensed.progress`.
검사/빌드: `tools/check_campaign30_lab.ps1 -Build` (다른 빌드가 있으면 대기).
현재 증거와 이전 번호 대응표: `docs/next_version_27이후/game_implementation_v7/`.

아래 0.4.0의 50레벨 설명은 이전 버전 기록이다. 실행/설치·게임 규칙·독립 앱 계약은 동일하다.

# 이전 50레벨 기록

독립 Flutter 게임 실험 앱이다. 기존 교대시계 dev/prod와 연결하지 않는다.
Android ID: `dev.shiftbell.experiments.sync_path_lab.dev`. Android에서는 devDebug만 존재한다.

## 실행 / 설치

반드시 이 디렉터리에서 실행한다.

```powershell
cd C:\Users\Administrator\Desktop\shiftbell\examples\sync_path_lab
flutter pub get
flutter run --debug --flavor dev
# 이미 빌드한 APK 설치
flutter install --debug --flavor dev
```

APK: `build/app/outputs/flutter-apk/app-dev-debug.apk`.
release/profile/prod 빌드, 기존 앱 연결 또는 자동 설치는 하지 않는다.
웹 검사: `flutter build web --debug --dart-define=SYNC_PATH_LAB_ENV=dev --no-web-resources-cdn --no-wasm-dry-run`.
`node tools/serve_dev.mjs`로 loopback 8781 포트에서만 열 수 있다.

## 현재 규칙

런타임 ruleSet은 `constant-cell-speed-v2`다. 모두 동시에 출발하고 기본 1.5배 속도(한 칸 약433.3ms)로 재생한다.
긴 명령은 이동한 칸 수만큼 더 오래 걸린다. Unit별 다음 명령은 앞 명령 직후 이어진다.
최대 N은 종점을 고른 횟수다. 직선 분할만으로 시간차를 만들 수 없지만 왕복/우회는 가능하다.
같은 절대 시각에 중심이 일치하면 칸 사이에서도 충돌한다. Goal은 즉시 흡수하며 동시 도착을 허용한다.

50레벨 모두 바로 선택 가능한 실험 설정이다. 1–5는 분리 경로→쉬운 교차 회피→필수 우회 튜토리얼이다.
1–14는2공,15–29는3공,30–50은4공이고 보드는5×5/6×6/7×7이다. 한글/영문 제목과3단계 힌트를 제공한다.
모든 시작점은 Goal과 Manhattan 거리3 이상이며,4번 이후 각 공의 최소 경로는4칸 이상/2명령 이상이다. 작은 판에도 어려운 문제를 배치한다.
지도50개의 바닥 구조는 회전/반사를 고려해도 서로 다르고, 후반에는2~3공의 우회가 반드시 필요하다. 분석 난이도와5레벨 평균은 증가하지만 인간 체감 난이도는 실기기 플레이로 확인해야 한다.
저장 키 `syncPathLab.dev.v4.campaign50.progress`는 옛 v1/v2/v3 기록을 덮어쓰지 않는다.

## 표현 / 의존성

이미지 없이 색/표면 무늬가 다른5종 공과 입체 블록 타일을 Canvas로 그린다. 5레벨 구간별 포인트 색과10레벨마다 바닥/벽의 얕은 표면 디테일이 바뀐다. 별도 이미지/테마 에셋은 없다.
선택 확대/표식, 거리 기반 좌우·상하 회전, Idle, Goal 점프, 충돌/성공 입자 표현을 제공한다.
새 규칙의 현재 기본 이동은 모든 Unit에 같은1.5배를 적용한다. 회전은 절대 재생 위치에서 구하고 게임 속도/충돌을 바꾸지 않는다.
사운드와 Flame 의존성은 없다. 엔진에는 이미지, FPS, 시각 시계가 들어가지 않는다.

런타임 의존성은 Flutter → UI/core와 shared_preferences다. tools/Solver/인증서/기존 앱 서비스는 들어가지 않는다.
로그인/광고/알람/권한 서비스가 없다. debug merged manifest에는 Flutter 디버깅용 INTERNET과 AndroidX 자체 signature permission이 포함된다.

30레벨 설계/독립 Solver 증거는 `docs/next_version_27이후/game_implementation_v4/`에 보존한다. 경량화0.3.1+5 당시 증거는 `game_implementation_v5/`, 현행0.4.0+6 /50레벨은 `game_implementation_v6/`다. `tools/check_campaign50_lab.ps1 -Build`는 폰트/44 UI·호스트 검사/dev debug APK/웹을 확인한다. 기존 rules/Solver의 검사는 v4 증거를 유지하며 재실행하지 않았다.
종전 문서의 shared-goal-v1/동일 Step 시간 계약은 역사적 검증용이며 이 앱의 현행 규칙이 아니다.


선택 안내는 공의ID/무늬와 다음 종점 수를 보여 준다. 선택한 공은 약1.22배/자체 색 링/상단 표식으로 표시하고, 갈 수 있는 종점은 같은 색으로 채운다. 다른 공은 계획 중 살짝 흐리게 한다. 320px에서도7×7이44px 칸으로 전부 보이도록 수평 페이지 여백을 공통 토큰에서 줄인다. 모든 컨트롤은 세로 스크롤로 접근할 수 있다.

빌드 실행기는 다른 Flutter build/Gradle wrapper 빌드 프로세스가 있으면 대기 후 순서대로 dev debug→웹을 빌드한다. 독립 lab의 Gradle 힙2GB/작업자2개/단일 사용 daemon/in-process Kotlin 설정은 기존 프로젝트의 빌드 설정을 바꾸지 않는다. 다른 세션의 프로세스를 종료하지 않는다.
