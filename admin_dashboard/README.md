# 교대시계 관리자 대시보드

출시된 앱(Play Store, prod)의 사용 현황을 **모바일에서 한눈에** 보는 개인용 웹페이지입니다.
Firebase Hosting + Auth + Firestore 무료 한도 안에서 동작하고, **앱 빌드(aab)에는 포함되지 않습니다**
(`pubspec.yaml`의 assets에도 없고 `android/`·`lib/`와도 무관한 웹 전용 폴더).

```
앱(prod) ─ Firebase Analytics ─▶ GA4 ─(Data API, 매일 한국 시간 12:17에 조회)─▶ sync.mjs ─▶ Firestore dashboard/* ─▶ 이 사이트(로그인 후 읽기)

앱 사용 지표는 출시 앱 스트림만 쓴다. 친구 웹 뷰어 성공 열람은 웹 스트림에서 따로 조회해 최근 30일 요약으로만 표시한다. 웹 방문을 앱 DAU에 합치지 않는다.
```

## 무엇이 보이나

- **핵심 지표**: 기간 활성/신규 사용자, D7 재방문, MAU, GA4 첫 실행, 감지된 삭제, 세션, 평균 사용 시간, 광고 노출·수익. 첫 실행은 Analytics 도입 업데이트도 포함될 수 있으므로 순수 신규 설치 수로 해석하지 않는다.
- **기준일**: 핵심·광고·일별 행동은 어제까지의 완료된 날짜를 조회한다. 버전/기기 등 분포는 어제까지의 최근 28일이다. 같은 기간의 중복 제거 사용자 수와 일별 횟수를 구분해서 읽는다.
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
| `../.github/workflows/dashboard-sync.yml` | 한국 시간 12:17 매일 자동 동기화(시크릿이 없으면 실패로 표시, 예약 실행 지연 가능) |

기존 친구 공유 웹(`build/web`, 루트 `firebase.json`, `shiftbell-29f31.web.app`)은 **건드리지 않습니다.**
이 대시보드는 같은 Firebase 프로젝트의 **별도 호스팅 사이트**입니다.

## 보안

- 로그인은 Firebase 이메일/비밀번호 인증. 규칙(`firestore.rules`)이 **`rlaworms0905@naver.com` + `email_verified == true`** 인 사용자만
  `dashboard/*`를 `get`으로 읽게 합니다(list·write는 전부 거부).
- 관리자 계정은 **반드시 `admin-user.mjs`(Admin SDK)로 만들 것** — `emailVerified:true`로 만들어지므로,
  누군가 같은 이메일로 먼저 가입해 선점하는 공격이 막힙니다. 공유 기능의 익명 가입을 위해 사용자 생성 허용은 유지합니다(아래 설정 기준).
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
   (이후 자동: GitHub 저장소 Settings → Secrets → `GA4_SERVICE_ACCOUNT_JSON`에 키 JSON 전체를 넣으면 Actions가 매일 한국 시간 12:17에 실행)
7. **배포**: `cd admin_dashboard && node tools/build.mjs && firebase deploy --only hosting --project shiftbell-29f31` → `https://shiftbell-ops-29f31.web.app`
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


## 운영 집계 (2026-10-11)

- 서버는 매일 한국 시간 12:17 한 번 예약합니다(UTC cron 17 3 * * *). 예약 실행은 지연될 수 있습니다.
- sync.mjs는 같은 한국 날짜에 이미 pipelineVersion 2 집계가 있으면 API를 다시 호출하지 않습니다. 관리자가 의도적으로 재집계할 때만 --force를 씁니다.
- 조회는 어제까지입니다. GA4 최근 24~48시간 값은 이후 집계에서 보정될 수 있습니다. 화면이 36시간 이상 갱신되지 않으면 집계 지연으로 표시합니다.
- 화면 새로고침은 저장된 문서를 다시 읽습니다. 약 10~11분 재조회는 서버 집계를 실행하지 않습니다.
- summary/series/events/operations 문서는 하나의 Firestore batch로 저장합니다. 중요 리포트 실패 시 기존 집계를 보존합니다. 부가 리포트 실패·빈 값·비공개 임계값/표본/행 제한은 화면에서 구분합니다.

## 사업 운영 화면

- 운영 요약: 같은 기간의 중복 제거 활성/신규 사용자, 재방문, 기능 도달, 알람 관측, 광고 수익, 수집 상태.
- 성장·국가: 국가별 활성·신규·온보딩·전체조 생성·알람 활용, 직전 동일 기간 대비, 국가별 최근 최대 100일 추이.
- 기능 활용: 사용자 수/같은 기간 totalUsers 기준 도달률/이용 횟수. 여러 기능 사용자를 더해 합계 이용자로 만들지 않으며 기간별 기능 도달을 전환 퍼널로 부르지 않습니다.
- 알람·기기: 제조사별 예약 API 실패·울림 진입·갱신 실패·배터리 최적화 적용·정확 알람 미허용 관측. 예약 완료와 실제 울림, 무응답을 동일 단계로 계산하지 않습니다.
- 기존 스트림 분리는 유지합니다. 앱은 prod Android만, 웹 친구 열람은 별도 요약이며 dev Analytics는 OFF입니다.
- H선은 차트 탭/드래그 후 유지하고 다른 영역 터치나 Escape에 해제합니다. 차트 교체 때 전역 listener를 제거합니다.

## 새 앱 계측과 한계

전체교대조 생성·조 변경·삭제는 저장 성공 뒤에 기록합니다. 근무표 내용/근무명/조 이름을 보내지 않습니다.
OperationsSnapshot은 이미 남는 로컬 진단 로그를 앱 재개 시 백그라운드에서 읽습니다. 알람 예약·울림·부팅 경로에는 네트워크나 Firebase 호출을 추가하지 않습니다.
최근 72시간, 최근 최대 1,000개 관측, 종류별 회당 40건 상한이며 첫 실행은 기존 로그를 제외하는 기준선만 만듭니다. 보고 날짜는 실제 사건 날짜가 아니라 앱을 연 날짜입니다. OS 권한/배터리 상태는 기기 날짜별 하루 1회 보고합니다.
새 운영 이벤트는 새 계측 앱이 prod로 출시된 이후부터 들어옵니다. 과거 데이터는 소급 복원하지 않습니다. 예약/재시도 횟수를 알람 수신율로 계산할 수 없고, 무응답을 미울림으로 판정할 수 없습니다.
강제종료 후 미울림·배터리 제한이 직접 유발한 실패·Crashlytics 오류율은 별도 검증 근거가 없으며 성공이나 0% 장애로 표시하지 않습니다. Crashlytics SDK를 새로 넣지 않았습니다.
광고 수익 미연결은 수익 0원이 아닙니다. 결제·광고 비용·운영 원가를 연결하지 않아 순이익/ROI를 계산하지 않습니다.

## 웹 빌드와 배포

이 사이트는 Flutter 공유 웹과 별개인 정적 웹입니다.

    cd admin_dashboard
    node tools/build.mjs
    firebase deploy --only hosting --project shiftbell-29f31

빌드는 JavaScript 구문을 확인하고 public/을 admin_dashboard/build/에 복사하며 build-info.json의 버전과 파일 해시를 생성합니다. Firebase Hosting site는 shiftbell-ops-29f31만 배포합니다.


2026-10-11 후속: 운영 요약의 첫 카드는 어제 DAU/어제 기준 MAU와 최근 10일 고정 추이다. 차트/날짜 버튼으로 하루씩 확인하고, 다른 조회 기간은 아래 기간 지표에 적용된다. 어제 집계가 없으면 대기로 표시하며 과거 값을 어제로 바꾸지 않는다. 핵심 기능 표는 선택 기간 이용 횟수 내림차순, 미관측은 마지막이다. 고정 질문 제목은 제거했다. 친구 공유 웹·Auth/Firestore 규칙은 수정하지 않았다.
