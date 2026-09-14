# G5 실제 데이터 수집·전송 목록 초안

> T09 정적 코드 조사 초안이다. 제품 기준 `c0b2e73`과 T07/G2 handoff를 대조했다. Firebase/AdMob/Play Console 실제 설정, release merged manifest, 네트워크 캡처는 확인하지 않았으므로 T22~T24에서 `확정/미확인`을 분리해 갱신한다.

## 외부 전송

| 경로 | 시작 조건 / 수신자 | 코드에서 확인한 데이터 | 포함되지 않는 것으로 확인한 데이터 | 현재 확인 상태 |
|---|---|---|---|---|
| Firebase Analytics | `initFirebase()` 성공 뒤 `setAnalyticsCollectionEnabled(true)`; Google Firebase Analytics | 커스텀 이벤트 없이 SDK 자동 수집 이벤트만 사용. 앱 인스턴스·세션·first_open/screen_view 등 SDK 자동 항목 가능 | 코드상 custom event, user ID, user property, 메모/OT/수면/근무표 payload 전송 호출 없음 | 실제 DebugView·보존기간·광고 기능 연결은 S12/T24 미확인 |
| Firebase Anonymous Auth | 친구공유에서 현재 user가 없을 때 `signInAnonymously()`; Firebase Authentication | 익명 UID와 인증에 필요한 SDK 기술 데이터 | 이름·근무표는 Auth credential 자체에 넣지 않음 | Console의 Anonymous 활성화·계정 보존/삭제 정책 미확인 |
| Firestore `friend_schedules/{uid}` 쓰기 | 공유 시작, 이름/근무표 변경, G2 retry; Firebase/Google | 문서 ID=익명 UID, `ownerName`, `isRegular`, `pattern`, `todayIndex`, `startDate`, `shiftColors`, `assignedDates`, 서버 `updatedAt` | 메모, OT, 근로시간 `shiftDurations`, 알람 설정/이력, 일정, 수면 기록 | G2 `5cda0e0`: dirty/generation/fingerprint는 로컬 상태이며 서버 payload 필드 아님. D7 tombstone/rules는 미구현 |
| Firestore 친구 조회 | 코드/링크의 ownerId로 source=server 조회; Firebase/Google → 친구 기기 | 위 공유 문서 전부. 성공 결과를 로컬 `friends.data_json` 캐시에 저장 | 소유자의 다른 로컬 데이터 | 규칙은 단일 문서 get 공개, list 거부. 운영 rules 배포 상태 V5 미확인 |
| Firestore `app_config/android` | 시작/resume 최대 6시간 주기; Firebase/Google | `latestVersionCode` 등 공개 앱 설정 읽기 | 사용자 앱 데이터 전송 호출 없음 | 읽기 요청의 SDK/네트워크 메타데이터는 서비스 측 처리 가능; Console 확인 필요 |
| Firestore `health_tips` | 컨디션 provider 최초 로드; Firebase/Google | 공개 `icon/title/content` 문서 목록 읽기 | 사용자 앱 데이터 전송 호출 없음 | 오프라인/실패 시 로컬 목록 사용 |
| Google Mobile Ads | 앱 시작 `MobileAds.initialize`, 배너 `AdRequest`; Google AdMob | SDK 광고 요청·응답 및 기기/앱/광고 상호작용 관련 데이터가 수집될 수 있음 | 앱 코드가 메모/OT/수면/근무표를 광고 요청 extras로 넣지 않음 | 현재 앱 ID·unit ID는 테스트 ID, debug tint=true. release 실제 ID, 동의 흐름, SDK가 merge한 AD_ID 권한, 데이터 보안 항목은 T21/T23/T24 확인 필요 |
| OS 공유 시트 | 사용자가 친구 공유 버튼 선택; 선택한 외부 앱 | 표시 이름, 웹 링크, `SB2:<ownerId>` 코드가 포함된 텍스트 | 근무표 본문·메모·OT·알람·수면은 직접 첨부하지 않음 | 수신 앱의 수집·보존은 해당 앱 정책 대상임을 안내문에 구분 |
| Play Store 링크 | 사용자가 업데이트 버튼 선택 | 패키지 ID가 포함된 공개 URL open | 앱 사용자 데이터 payload 없음 | 단순 외부 이동 |
| Google Fonts 가능 경로 | `google_fonts` 사용, 런타임 fetching 비활성 코드 미발견 | 글꼴 요청 시 IP/기기 네트워크 메타데이터가 전달될 가능성 | 앱 DB payload를 직접 붙이는 코드 없음 | release asset 포함 여부와 실제 네트워크 요청을 T23에서 캡처해 확정 |

Firebase 초기화는 `main.dart`와 웹 진입점에서 시도하며, 실패하면 선택 기능을 no-op/fallback 처리한다. `AndroidManifest.xml`에는 `INTERNET` 권한이 있다.

## 기기 내 저장·백업

| 저장소 | 실제 내용 | 외부 전송 여부 | G4/G5 조치 |
|---|---|---|---|
| Device Protected SQLite | `alarm_types`, `alarms`, `shift_schedule`, `shift_alarm_templates`, `date_memos`, `alarm_history`, `alarm_creation_log`, `date_overtime`, `friends`, `date_schedules`, `condition_shift_times`, `sleep_records`, `alarm_overrides` 등 | 앱 자체 서버 업로드 없음. 친구공유가 위 제한 필드만 별도 Firestore 전송 | 개인정보 안내에는 로컬 저장 범주 설명. 복원/삭제 범위와 영구 이력 정책 표시 |
| Flutter SharedPreferences | 권한, 테마, 탭, 근무시간/급여기간, 전체 조, 튜토리얼, 업데이트, 백업 상태, 친구공유 상태·이름 | Firebase 전송은 공유 이름/상태 동작에 필요한 부분만. 현재 백업에는 전 키 포함 | G4가 공유 소유권 7키·백업 휘발키를 제외하고 허용 목록/범주 확정 |
| Native DP prefs | 알람 refresh/boot/lock/current ring, 수면 감지 표본·거부 학습 | 백업 안 됨, 네트워크 전송 코드 없음 | 복원 재조정용 현재 기기 상태로 취급 |
| MediaStore `Download/ShiftBell` JSON | 현재 `BackupService`가 `alarms`와 시스템 테이블을 제외한 SQLite 테이블 전부 + Flutter prefs 전부를 평문 JSON으로 작성 | 네트워크 업로드 없음. 사용자가 파일을 다른 앱/클라우드 폴더로 옮기면 그 수신처 정책 적용 | 저장 위치·평문·포함 범주·삭제/덮어쓰기·재설치 탐색 한계를 안내. 완성 전 파일 비노출 및 이전 정상본 보존 필요 |
| 로컬 친구 캐시 | ownerId, 표시 이름, 마지막 성공 공유 payload, added/updated 시각 | 친구 조회 때 Firestore read; 캐시는 자동 업로드하지 않음 | 서버 문서 삭제/revoked와 offline을 구분. 캐시 삭제 시점 안내 |
| 웹 `localStorage` | `shiftbell_last_owner_id` | 브라우저 기기 내 저장 | 웹 개인정보 문구·삭제 방법 검토 |

현재 백업은 동적 테이블 열거 방식이라 `alarms` 외 신규 테이블도 자동 포함한다. 따라서 “일부 설정만 백업”이라고 안내하면 실제와 다르다. `alarm_history`, 메모, OT, 일정, 수면, 친구 캐시처럼 민감할 수 있는 내용이 평문 파일에 포함된다.

## 코드상 미발견

- Firebase Crashlytics, Performance Monitoring, Remote Config SDK/호출.
- 연락처, 위치, 사진, 마이크, 카메라, SMS, 통화기록 권한과 수집 코드.
- 사용자 메모·OT·수면·알람 이력을 Firestore/Analytics/AdMob payload에 넣는 호출.
- 자체 HTTP 서버나 `http`/`dio` 기반 사용자 데이터 업로드.

“미발견”은 의존 SDK의 자동 수집 부재를 뜻하지 않는다. release 의존성·merged manifest·Console 설정과 실제 네트워크를 함께 봐야 한다.

## T22~T24 확정 체크리스트

1. dev/prod release 각각 `Firebase.app().options`와 Analytics DebugView 목적지를 기록한다.
2. Analytics 자동 이벤트·광고 신호·Google Signals·보존기간·데이터 삭제 설정을 Console에서 확인한다.
3. AdMob 실제 앱/광고 단위 ID, 테스트 기기 처리, UMP/동의 요구 지역, merged manifest의 `AD_ID`를 확인한다.
4. Firestore 운영 rules가 저장소 rules와 일치하는지, friend 문서 실제 필드와 크기를 확인한다.
5. G4 최종 backup allow/exclude 목록으로 위 MediaStore 행을 다시 작성하고 샘플 JSON의 실제 키를 대조한다.
6. release 네트워크 캡처로 Analytics, Firestore, Ads, Google Fonts의 실제 endpoint/trigger를 구분한다.
7. Play 데이터 보안 양식과 앱 내 ko/en 안내를 각각 `수집`, `공유`, `기기 내 처리`, `사용자 선택 전송`으로 매핑한다.
