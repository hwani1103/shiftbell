# G2 handoff

```text
그룹 / 담당 / worktree / branch: G2 / Codex / C:\Users\Administrator\Desktop\shiftbell-g2 / release/g2
공통 기준 SHA / 최종 소스 SHA: c0b2e73 / 5cda0e09707d763528a59b90e0b2b5df71c0a86c
상태: CODE_FROZEN (T07, 2026-09-14) — PROVISIONAL / G0 실기기(T04-D) 미통과 상속
수정한 감사 번호: #21, #24, #29(정적 조사만; S12 NOT_RUN), #30. D7 앱 측 상태 머신만, D8 설정 변경 없음
실제 변경 파일(소유권 범위 검사 결과): G2 허용 범위 6개. 범위 밖 제품 파일 수정 없음
  - lib/services/friend_sync_service.dart
  - lib/services/friend_share_service.dart
  - lib/models/friend_schedule.dart
  - lib/providers/friend_provider.dart
  - lib/screens/friend_list_screen.dart
  - lib/utils/friend_open_util.dart
공통 파일/API/ARB 연결 요청 및 반영 SHA: g2/integration_requests.md G2-01~04. 미반영(`-`), T10/G4/G5 대상
사용자 결정 확인(D 번호·선택·일시): D1~D12 전부 확정(2026-09-14, 실행계획 §4). PROVISIONAL / G0 실기기(T04) 미통과 상속
  - D7: S9 뒤 tombstone/rules 후속 선택. 이번에는 `firestore.rules`·웹 배포·운영 배포 수정 안 함
  - D8: S12 뒤 dev Firebase 분리 후속 선택. 프로젝트/Console/플랫폼 설정 수정 안 함
최종 동작과 회귀 금지 규칙 준수:
  - 로컬 의도 off/active/stop_pending, dirty, 단조 generation을 Flutter prefs에 영속. generation은 새 공유 시작 회차에만 증가
  - start/update/schedule 제출을 단일 큐로 직렬화하고 실제 set 직전에 intent/generation/최신 payload fingerprint 재검사. stop 이후 대기 중 payload는 제출하지 않음
  - Firestore write가 5초 안에 ACK되지 않아도 이미 접수된 작업을 취소됐다고 간주하지 않고 dirty/stop_pending 유지. 큐를 풀어 후속 stop을 SDK에 제출하고, 늦은 완료도 최신 회차 확인 뒤에만 상태 확정
  - 공유 필드(ownerName, 규칙/패턴/시작일/색/배정일)만 canonical fingerprint에 포함. shiftDurations·OT·메모·알람 무관 변경은 확인 완료 상태에서 재업로드하지 않음
  - 앱 시작/재개/네트워크 복구/복원 후 재시도 API 제공. 실제 lifecycle 연결은 G2-01, 복원/백업 연결은 G2-03
  - 친구 조회는 Source.server 강제. 서버 확인 notFound/revoked만 로컬 등록·캐시 제거; offline/Firebase 미준비/오류는 캐시 유지와 확인 불가 상태 표시
  - refreshAll은 최초 SQLite load를 기다린 뒤 친구별 fetch/update하고 마지막에 load 1회. 첫 frame 빈 state 경합과 친구 수만큼 전체 재조회 제거
  - ownerId 형식, 원격/캐시 payload 자료형·날짜·크기·정규 패턴 관계 방어. active payload는 800KiB 상한. malformed 문서를 빈 근무표로 표시하지 않음
추가/변경 테스트와 실제 실행 명령: 없음(수정 단계). 사용자 병행 예외로 flutter/gradle 빌드·테스트·pub get·analyze 전부 실행 금지. 테스트 코드도 T13까지 작성/실행하지 않음
  - 읽기 전용/정적 확인: `git diff --check c0b2e73..HEAD`, `git show --check --stat` 두 커밋, branch/HEAD/status/변경 경로 대조
  - `dart format`은 Flutter SDK 동시 사용 중 완료 출력 없이 대기하여 중단. 성공 증적으로 취급하지 않음
테스트 결과(실행 빌드·환경·expected/actual·증적): NOT_RUN — CODE_FROZEN은 자동/에뮬레이터/실기기 PASS를 뜻하지 않음
미실행 실기기/Console 항목: T13 F/Firestore rules emulator/E 전체, S9 두 기기, S12 실제 Firebase.app().options·DebugView, S18(D7 선택 시), 운영 rules V5
잔여 위험·다음 그룹 주의사항:
  1. G2-01/02가 연결되기 전에는 재시작·재개 retry와 pending 사용자 표시가 완결되지 않음. 현재 저장 변경 경로의 syncIfEnabled만 연결돼 있음
  2. D7 전에는 서버 tombstone/rules 강제가 없어 구버전 앱·다른 클라이언트가 늦게 보낸 set의 부활을 앱 gate만으로 막을 수 없음. 현재 stop은 호환 delete 유지
  3. 현재 rules는 필드/형/크기를 서버에서 제한하지 않음. 앱 입력 방어만 추가했으며 D7 선택 후 rules와 S18 필요
  4. 정적 조사: prod/dev 모두 Firebase project `shiftbell-29f31`. google-services.json에는 패키지별 app id가 있으나 Dart init이 Android prod app id를 명시함. 실제 dev 런타임 appId/Analytics 목적지는 S12 없이는 확정 금지
  5. 익명 인증 UID가 재설치로 바뀌면 옛 문서를 회수/삭제할 수 없는 기존 한계 유지. 공유 키 전부를 백업 제외하도록 G4 연결 필수
  6. 5초 timeout은 서버 실패 판정이 아니라 로컬 pending 전환값. 느린 정상 네트워크에서도 pending이 보일 수 있으며 T13/S9에서 전이·호출량 측정 필요
  7. 빌드·analyze·format·테스트 미완료이므로 컴파일 결함 가능성은 T10 빌드 가능 확인/T13에서 해소
```

## G2 신규 Flutter prefs 키 등록부

| 키 | 형 / 기본 | 소유·쓰는 곳 | 백업 | 저장 실패 / 의미 |
|---|---|---|---|---|
| `friend_share_intent` | String `off` (`off/active/stop_pending`) | G2 `FriendSyncService` | 제외 요청 | authoritative 의도. 기존 enabled=true 설치는 active generation 1 + dirty로 승격 |
| `friend_share_dirty` | bool false | G2 | 제외 요청 | 실패/timeout이면 true 유지, 동일 최신 payload 서버 확인 뒤만 false |
| `friend_share_generation` | int 0 | G2 | 제외 요청 | 새 공유 시작 회차에만 +1. 이름/근무 수정에는 불변 |
| `friend_share_desired_fingerprint` | String 없음 | G2 | 제외 요청 | 최신 공유 payload의 canonical JSON. 옛 queued set 차단 |
| `friend_share_confirmed_fingerprint` | String 없음 | G2 | 제외 요청 | 서버 확인 완료 payload. 같고 dirty=false일 때 write 생략 |

기존 `friend_share_enabled`와 `friend_share_my_name`도 함께 백업 제외 요청했다. SharedPreferences setter가 false면 성공으로 삼지 않고 상태 저장 실패로 처리한다.

## G2 writer 목록 (T09/G4 입력)

| 파일 / 함수 | 쓰는 대상 | 트리거 / 실행 컨텍스트 |
|---|---|---|
| `friend_sync_service.dart` `startSharing`, `updateMyName`, `syncIfEnabled`, `stopSharing`, `retryPending` | Flutter prefs 7키; Firestore `friend_schedules/{uid}` set/delete | UI 시작·이름·중지, schedule commit 후 비동기 호출, 향후 lifecycle/reconnect. 단일 Dart 제출 큐 |
| `friend_sync_service.dart` 늦은 ACK callback | dirty/confirmed fingerprint/intent | Firestore write Future가 5초 이후 완료. 최신 intent/generation/fingerprint 일치 때만 기록 |
| `friend_sync_service.dart` `onRestoreCompleted` | dirty 및 현재 상태에 따른 Firestore 재시도 | G4 복원 완료 후 연결 예정. 복원 owner token/gate는 G4 소유, G2는 구현하지 않음 |
| `friend_provider.dart` add/refresh/remove/rename | 기존 SQLite `friends` 캐시/등록 행 | 앱 UI. Source.server 확인 삭제/revoked만 자동 delete; offline은 DB 무변경 |

## 진행 기록 (끊김 대비 — 하위 작업마다 한 줄)

| 일시 | 담당 AI | T | 감사 번호 / 하위 작업 | 커밋 SHA | 다음에 할 일 |
|---|---|---|---|---|---|
| 2026-09-14 | Codex | T07 | #24 상태 머신·직렬 제출·dirty/generation/retry API + #21 server 강제 조회·캐시 상태 + #30 fingerprint/입력 제한·refreshAll 1회 load | `bf162ac` | 최초 cache load와 화면 진입 refresh 경합 재검토 |
| 2026-09-14 | Codex | T07 | #30 최초 load 완료 전 refreshAll이 빈 state를 확정하는 경합 수정 → CODE_FROZEN | `5cda0e0` | T10 연결 요청 G2-01~04 반영 후 빌드 가능 확인; T13 테스트 |

## T10 연결 (Claude, 통합 담당자, 2026-09-14)

- release/g2 `4a8f67e` = CODE_FROZEN `5cda0e0` + 연결 코드. **T13 테스트 대상 SHA = `4a8f67e`.**
- G2-01 반영: `lib/main.dart` `_MainScreenState` — `ref.listenManual(scheduleProvider, fireImmediately: true)`로 근무표 첫 로드(없음 포함) 뒤 `FriendSyncService.onAppStarted` 1회, `didChangeAppLifecycleState(resumed)`마다 `onAppResumed`. 둘 다 fire-and-forget, 오류는 `debugPrint`만. 앱에 네트워크 재연결 신호가 없어 `onNetworkReconnected`는 미연결.
- G2-02 반영: `lib/screens/my_share_code_screen.dart` — `getShareState()` 보관, active+dirty / stop_pending 배너 + "지금 다시 보내기"(`retryPending`), 이름 변경이 서버 확인 대기면 실패 대신 대기 안내, 중지 뒤 상태를 다시 읽어 확인 전이면 대기 배너(삭제 완료 문구 없음). ARB 4개 `friendSyncPendingBanner`·`friendStopPendingBanner`·`friendRetrySync`·`friendSyncPendingToast`(ko/en, friend 키 근처 — G1 ARB 추가 위치와 다른 곳).
- G2-03(G4)·G2-04(G5)는 T10 대상 아님.
- 확인: `flutter analyze lib/main.dart lib/screens/my_share_code_screen.dart` error 0(warning 1건 `_MyAppState.platform` 미사용은 기존), `flutter build apk --flavor dev --debug`(shiftbell-g2) exit 0, assembleDevDebug 313.7s. 테스트 코드 없음(T13), 설치·실행 안 함.

## T13 G2 테스트 (Claude, 2026-09-14)

- 대상 release/g2 `4a8f67e`. 테스트 코드만 추가(`test/release_audit/g2/`, 커밋 `0cbe392`), 제품 코드 무변경. 상세·판정: `g2/test_results.md`.
- F 40/40 PASS(상태 머신 15·친구 캐시 6·payload 경계 9·공유 코드 5·공유 화면 대기 안내 5), 전체 `flutter test` 179/179, `flutter analyze test/release_audit/g2` 이슈 0.
- FS(Firestore emulator, `demo-shiftbell-t13`) 16/16 PASS — 소유권·list 차단·기타 컬렉션·legacy 호환. 관찰 4건: 서버 형식·크기 검증 없음, delete 뒤 옛 회차 set 재생성, tombstone 회차 강제 없음(잔여 위험 2·3 확인, D7 입력).
- 판정: #21 부분 PASS(서버 확인 삭제 경로 S9), #24 로컬 상태 머신 PASS(서버 ACK·timeout·늦은 ACK 경로 S9), #29 NOT_RUN(S12), #30 앱 측 PASS.
- 코드 읽기 관찰(PLAUSIBLE, 미재현): 큐 작업 안의 `signInAnonymously`에 timeout이 없어 로그인 호출이 멈추면 뒤의 stop 제출도 대기. T16 입력.
- 주입 지점 없음: 서버 ACK/timeout 자동 테스트는 G2 코드 변경이 필요 — S9로 대신할지 T16 결정.
