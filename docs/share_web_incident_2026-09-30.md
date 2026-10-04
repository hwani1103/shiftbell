# 일정공유 웹 장애 확인 (2026-09-30)

## 운영에서 확인한 원인

- USB 연결된 테스트 앱의 공유 링크를 운영 Hosting에서 열어 재현했다.
- 해당 `friend_schedules` 문서는 비인증 REST get으로 HTTP 200이었고, `revoked=false` 및 정상 근무 패턴이 있었다. 공유 중지나 데이터 삭제가 원인이 아니다.
- 휴대폰 Chrome 콘솔에서 `FirebaseAnalyticsHostApi.setAnalyticsCollectionEnabled`의 `PlatformException(channel-error)`를 확인했다.
- 배포 웹은 Analytics 웹 플러그인 대신 네이티브 채널을 호출하고 있었다. 기존 로컬 웹 빌드의 `web_plugin_registrant.dart` 두 개에도 `FirebaseAnalyticsWeb.registerWith`가 빠져 있었다.
- `initFirebase()`가 Firebase Core와 Analytics를 같은 try/catch에서 초기화하면서 통계 오류까지 Firebase 전체 실패로 취급했다. 세 번 실패하면 `firebaseReady=false`가 되어 Firestore 조회를 시작하지 않았다.
- `app-ads.txt` 파일 자체와 공유 데이터의 접근 규칙은 이번에 관측한 오류 원인이 아니다. 플러그인이 누락된 빌드가 만들어진 정확한 과거 명령은 확인되지 않았다.

## 수정

`lib/services/firebase_bootstrap.dart`에서 Core 초기화 재시도와 Analytics 초기화를 분리한다. Analytics 오류는 로그에 남기고 `analytics=null`로 유지하되, 정상 초기화된 Firestore는 계속 사용할 수 있다. dev 앱의 통계 수집 비활성화 정책은 유지한다.

`test/firebase_bootstrap_test.dart`는 Analytics 채널이 없는 실제 오류 조건을 재현하고, `firebaseReady=true`가 유지되는지 검사한다.

현재 작업 트리의 간접 import에 포함된 `backup_policy.dart`의 모바일 전용 64비트 정수 리터럴도 JS 컴파일 오류를 일으켰다. 같은 값을 `int.parse`로 생성하도록 바꿔 모바일 계산을 유지하고 웹 컴파일을 통과시켰다. 이 함수가 웹용 64비트 해시 구현이 된 것은 아니다.

## 재빌드 확인

새 출력 경로로 웹을 빌드하여 기존 배포 산출물을 보존했다.

```powershell
flutter test test/firebase_bootstrap_test.dart
flutter build web --release -t lib/web_main.dart --no-wasm-dry-run --output .tmp/share-diagnosis/web
```

새로 생성된 웹 플러그인 등록 파일에 `FirebaseAnalyticsWeb.registerWith(registrar)`가 포함됨을 확인했다. `--no-wasm-dry-run`은 선택적 Wasm 호환성 검사만 생략하며 결과물은 기존과 같은 JavaScript 웹이다.

## 검증 결과

- 초기화 회귀 테스트, `app_analytics_test.dart`, `cross_review_backup_friend_test.dart`: 총 18개 통과.
- release 웹 빌드 성공.
- USB reverse로 로컬 빌드를 휴대폰 Chrome에서 열고 기존 운영 공유 문서를 조회했다. Firebase 첫 시도 초기화 성공 및 이름·2026년 9월 달력·주간/야간/휴무 표시를 스크린샷으로 확인했다.
- 검증 이미지: 로컬 `.tmp/share-diagnosis/verified.png` (개인 근무표 포함, 공개 첨부 금지).
- 사용자 재배포 승인 후 2026-09-30 운영 Hosting 배포 완료 (`shiftbell-29f31`).

## 운영 배포 및 확인

- 검증한 `.tmp/share-diagnosis/web`를 `firebase.deploy.json`으로 직접 지정해 Hosting만 배포했다. Firebase CLI에서 `release complete` 및 `Deploy complete` 확인.
- 기존 1일 캐시를 우회하도록 bootstrap에 `?v=share-fix-20260930`을 붙였고, `firebase.json`의 no-cache 대상에 `main.dart.js`를 추가했다. 소스 bootstrap에도 같은 변경을 반영했다.
- 운영 `main.dart.js`의 SHA-256이 검증 산출물과 일치: `2FE497462DC5E192C13DD6B32B2556745D048F868F4F479DE8C1B4185BF96C17`.
- 운영 응답 HTTP 200, `Cache-Control: no-cache`, bootstrap 캐시 우회 반영 확인. `app-ads.txt`도 HTTP 200이며 기존 내용과 동일.
- USB 휴대폰에서 운영 링크를 다시 열어 Analytics 웹 플러그인 등록과 Firebase 첫 시도 초기화 성공 로그를 확인했다. 기기 화면에서 공유 달력 정상 표시 확인 (`.tmp/share-diagnosis/verified-production-device.png`).

앱 재설치나 공유 코드 재발급은 필요하지 않다. 배포는 사용자에게 안내한 현재 작업 트리의 웹 변경을 포함한다.
