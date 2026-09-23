# 교대시계 관리자 대시보드

출시된 앱(Play Store, prod)의 사용 현황을 **모바일에서 한눈에** 보는 개인용 웹페이지입니다.
Firebase Hosting + Auth + Firestore 무료 한도 안에서 동작하고, **앱 빌드(aab)에는 포함되지 않습니다**
(`pubspec.yaml`의 assets에도 없고 `android/`·`lib/`와도 무관한 웹 전용 폴더).

```
앱(prod) ─ Firebase Analytics ─▶ GA4 ─(Data API, 3시간마다)─▶ sync.mjs ─▶ Firestore dashboard/* ─▶ 이 사이트(로그인 후 읽기)
```

## 무엇이 보이나

- **핵심 지표**: DAU / WAU / MAU, 끈끈이(DAU÷MAU), 신규 설치, 삭제, 세션, 평균 사용 시간, 광고 노출·수익
- **추세**: 7 / 30 / 100 / 365일 전환, 전 기간 대비 증감, 일별 표(그대로 복사·확인 가능)
- **사용자 행동**: 온보딩 완료, 알람 저장·끄기·5분 연장·무응답, 근무 지정, 메모, 일정, OT, 수면 기록, 백업, 친구 공유, 탭 이동 등
- **유지율**(코호트), 앱 버전/국가/기기 분포

## ⚠️ 집계 범위 — "출시된 앱만"

- GA4 조회는 전부 **prod 안드로이드 스트림(`15763725797`)** 으로 필터합니다(`sync/lib/ga4.mjs`, 테스트로 고정).
  dev 앱 스트림(`15763791924`)과 웹 스트림(`15763713126`, 친구 공유 뷰어)은 들어오지 않습니다.
- dev 플래버는 앱에서 Analytics 수집 자체를 끕니다(`firebase_bootstrap.dart`).
- **Analytics가 들어간 버전이 배포되기 전에는 값이 거의 비어 있는 게 정상**입니다(현재 GA4에는 소수 사용자 데이터만 있음).
  이번 업데이트(1.0.23)가 나가고 사용자가 앱을 열기 시작하면 채워집니다.
- **알람 횟수는 지연됩니다.** 알람은 Native(Kotlin)가 울리고 끄기 때문에 Firebase 코드를 그 경로에 넣지 않았습니다.
  대신 기기에 이미 남는 `alarm_history`에서 새로 쌓인 것만 **앱을 다음에 열 때** 보냅니다(`AlarmUsageAnalytics`) →
  "알람이 울린 날"이 아니라 "그 뒤 처음 앱을 연 날"에 집계됩니다.
- 앱은 **내용을 보내지 않습니다**(근무표·메모·수면 시각·알람 시각·친구 이름 없음). 종류·횟수 같은 분류값뿐입니다.
- 구글 집계 특성상 GA4 값은 하루쯤 늦고, 삭제(`app_remove`)는 실제보다 적게 잡힐 수 있습니다.

## 구성

| 경로 | 역할 |
|------|------|
| `public/` | 사이트 본체. 빌드 도구 없는 순수 ES 모듈(`assets/js/*`), 자체 SVG 차트, 라이트/다크, PWA |
| `sync/` | GA4 → Firestore 동기화(`sync.mjs`), 관리자 계정 생성(`admin-user.mjs`), 단위 테스트 |
| `tools/` | 로컬 에뮬레이터 실행·스크린샷/동작 검증(`start-emulators.mjs`, `shots.mjs`) — 배포 대상 아님 |
| `firebase.json` | 호스팅 전용 설정(사이트 `shiftbell-ops-29f31`, 보안 헤더·CSP·noindex) |
| `../firestore.rules` | `dashboard/{doc}` 읽기 규칙을 추가함(아래 "보안") |
| `../.github/workflows/dashboard-sync.yml` | 3시간마다 자동 동기화(시크릿이 없으면 건너뜀) |

기존 친구 공유 웹(`build/web`, 루트 `firebase.json`, `shiftbell-29f31.web.app`)은 **건드리지 않습니다.**
이 대시보드는 같은 Firebase 프로젝트의 **별도 호스팅 사이트**입니다.

## 보안

- 로그인은 Firebase 이메일/비밀번호 인증. 규칙(`firestore.rules`)이 **`rlaworms0905@naver.com` + `email_verified == true`** 인 사용자만
  `dashboard/*`를 `get`으로 읽게 합니다(list·write는 전부 거부).
- 관리자 계정은 **반드시 `admin-user.mjs`(Admin SDK)로 만들 것** — `emailVerified:true`로 만들어지므로,
  누군가 같은 이메일로 먼저 가입해 선점하는 공격이 막힙니다. 그래서 콘솔에서 **"사용자 가입" 허용은 끄세요.**
- Firebase 인증은 비밀번호가 **6자 이상**이어야 해서 `1234`는 만들 수 없습니다. 임시 비밀번호로 만든 뒤 사이트 안의
  **"비밀번호 변경"** 버튼으로 바꾸세요(현재 비밀번호 재확인 후 변경).
- 로그인 유지: 체크하면 브라우저에 유지(LOCAL), 안 하면 탭을 닫을 때까지(SESSION).
- 서비스 계정 키(JSON)는 **저장소에 커밋하지 마세요**(`.gitignore`에 패턴이 있음). GitHub Secrets에만 넣습니다.

## 1회성 설정 체크리스트 (배포 전)

콘솔/배포 작업은 직접 하는 것을 전제로 적었습니다. 운영 프로젝트(`shiftbell-29f31`)를 건드리는 단계라 자동으로 하지 않았습니다.

1. **Firebase 콘솔 → Authentication → 로그인 방법**: "이메일/비밀번호" 사용 설정.
   ⚠️ **설정 → 사용자 작업의 "생성 사용 설정(가입)"은 반드시 켜 둘 것.** 끄면 익명 가입까지 막혀(`ADMIN_ONLY_OPERATION`)
   앱의 친구 공유가 새 설치·재설치 기기에서 동작하지 않는다(2026-09-23 실제로 발생 후 복구). 켜 둬도 대시보드는 안전함 —
   규칙이 관리자 이메일 + `email_verified`를 요구하고, 관리자 이메일은 이미 등록돼 있어 다른 사람이 같은 이메일로 가입할 수 없다
2. **호스팅 사이트 추가**: 콘솔 → Hosting → "다른 사이트 추가" → 사이트 ID `shiftbell-ops-29f31`
3. **Firestore 규칙 반영**: 루트 `firestore.rules`의 `match /dashboard/{document}` 블록을 콘솔 규칙에 붙여 넣고 게시
   (또는 `firebase deploy --only firestore:rules` — 콘솔 규칙과 다르지 않은지 먼저 비교할 것)
4. **서비스 계정**: GCP 콘솔 → IAM → 서비스 계정 생성 → 키(JSON) 발급
   - Google Cloud에서 **"Google Analytics Data API" 사용 설정**
   - GA4 속성 `553838010` → 관리 → 속성 액세스 관리에 서비스 계정 이메일을 **뷰어**로 추가
   - Firestore 쓰기 권한: 같은 서비스 계정에 **Cloud Datastore 사용자** 역할, 계정 생성에는 **Firebase Authentication 관리자** 역할
     (계정 생성용은 1회만 필요하면 로컬에서 본인 계정으로 실행해도 됨)
5. **관리자 계정 만들기(1회)**
   ```bash
   cd admin_dashboard/sync && npm ci
   SERVICE_ACCOUNT_JSON="$(cat 키파일.json)" ADMIN_EMAIL=rlaworms0905@naver.com ADMIN_PASSWORD='임시비밀번호(6자 이상)' npm run admin-user
   ```
6. **첫 동기화**: `SERVICE_ACCOUNT_JSON="$(cat 키파일.json)" npm run sync`
   (이후 자동: GitHub 저장소 Settings → Secrets → `GA4_SERVICE_ACCOUNT_JSON`에 키 JSON 전체를 넣으면 Actions가 3시간마다 실행)
7. **배포**: `cd admin_dashboard && firebase deploy --only hosting` → `https://shiftbell-ops-29f31.web.app`
8. **AdMob ↔ Firebase 연결**(광고 수익·노출을 보려면): AdMob 앱 설정에서 Firebase 연결. 안 하면 광고 카드는 비어 있고 나머지는 정상
9. 휴대폰에서 접속 → 로그인 → 홈 화면에 추가(PWA)

> Play Console **데이터 보안 양식**과 앱 안 **개인정보처리방침**도 함께 확인하세요.
> 방침에는 "기능 사용 횟수만 기록, 내용은 미전송"이 반영되어 있고(2026-09-22), Play 양식의 "앱 활동"(앱 상호작용) 항목이 수집으로 표시돼 있어야 합니다.

## 로컬 개발·검증

```bash
cd admin_dashboard/tools && npm ci
node start-emulators.mjs                       # Auth 9099 · Firestore 8080 · Hosting 5010 (별도 터미널)
cd ../sync && npm ci
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 npm run seed:emulator
                                               # 모의 데이터 + 관리자/일반 계정(에뮬레이터 환경변수가 없으면 중단 — 운영 보호)
cd ../tools && node shots.mjs                  # Chrome(Samsung Internet UA 포함)으로 28개 시나리오 검증 + 스크린샷
cd ../sync && npm test                         # 동기화 변환 단위 테스트
```

Dart 쪽 이벤트 이름과 이 사이트의 이벤트 목록(`public/assets/js/labels.js`)이 어긋나면
`flutter test test/app_analytics_test.dart`가 실패합니다. **이벤트를 추가/변경하면 두 곳을 같이 고치세요.**

## 문제 해결

| 증상 | 확인 |
|------|------|
| 로그인 후 "권한이 없어요" | 계정이 `admin-user.mjs`로 만들어졌는지(emailVerified), 규칙이 게시됐는지, 이메일 철자 |
| 데이터가 전부 비어 있음 | 동기화를 한 번이라도 돌렸는지(`dashboard/summary` 문서 존재), 아직 Analytics 포함 버전 배포 전인지(이 경우 동기화는 성공하고 "아직 집계된 날짜가 없어요"가 뜸 — 기존 데이터가 있는데 0건이 오면 덮어쓰지 않고 실패) |
| 사용자 행동이 비어 있고 세션·DAU만 있음 | 계측이 들어간 버전(1.0.23+)이 배포됐는지 — 이전 버전은 이벤트를 보내지 않음 |
| 광고 노출·수익이 0 | AdMob ↔ Firebase 연결, prod release 빌드에서만 실광고 요청 |
| 동기화가 403 | 서비스 계정이 GA4 속성에 뷰어로 추가됐는지, Analytics Data API가 켜져 있는지 |
| Actions가 아무 것도 안 함 | Secret `GA4_SERVICE_ACCOUNT_JSON`이 비어 있으면 일부러 건너뜀 |
