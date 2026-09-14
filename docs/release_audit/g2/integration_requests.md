# G2 연결 요청

> 다른 그룹 소유 파일이나 공통 파일(main.dart, MainActivity.kt, DB 서비스, pubspec, Gradle, Manifest, l10n)이 필요하면 직접 고치지 말고 여기에 적는다. 통합 담당자(Claude)가 연결 단계(T10 등)에서 반영한다.

| # | 대상 파일 | 이유 | 필요 API / 변경 | 호출 시점 | 실패 시 의미 | 반영 SHA |
|---|---|---|---|---|---|---|
| G2-01 | `lib/main.dart` 및 앱 lifecycle 소유 파일 | dirty/stop_pending은 앱 재시작·재개 후 현재 상태로 재시도해야 함. G2는 병렬 구간의 main 소유권 없음 | 현재 `ShiftSchedule?`을 넘겨 `FriendSyncService.instance.onAppStarted(schedule)`와 `onAppResumed(schedule)` 호출. 실제 네트워크 재연결 신호가 이미 있으면 `onNetworkReconnected(schedule)`도 호출. Future 오류는 선택 서비스 오류로 기록하고 앱 시작을 막지 않음 | Firebase 초기화 시도와 schedule 로드가 끝난 뒤 앱 시작 1회; resumed; 연결 복구 | 미연결 시 현재 저장 경로의 다음 변경 때만 재시도되어 stop_pending/dirty가 오래 남을 수 있음 | `4a8f67e` (release/g2 T10 연결 — MainScreen: 근무표 첫 로드 뒤 onAppStarted 1회, resumed마다 onAppResumed. 네트워크 재연결 신호는 앱에 없어 미연결) |
| G2-02 | `lib/screens/my_share_code_screen.dart`, 공통 ARB | 현 화면은 bool만 보므로 서버 ACK 대기/실패를 표시하지 못하고, start가 pending이면 완료처럼 보이며 stop_pending도 단순 off처럼 보임 | `getShareState()`의 `intent/dirty`를 읽어 active-pending 및 stop_pending 안내·재시도 UI 제공. 시작/이름 변경/중지 결과와 로컬 의도를 구분. 서버 확인 전 "삭제 완료" 문구 금지. 필요한 ko/en ARB 추가 | 화면 load, 각 작업 완료, 수동 재시도 | 미연결 시 로컬 상태 머신은 보존되지만 사용자에게 pending 사실을 충분히 설명하지 못함 | `4a8f67e` (release/g2 T10 연결 — 공유 화면 active+dirty/stop_pending 배너·재시도, ARB 4개. 빌드 확인은 작업판 T10 행) |
| G2-03 | G4 `backup_service.dart` / restore 연결 파일 | 새 UID 설치에 옛 공유 상태를 복원하면 소유권과 회차가 어긋남 | `FriendSyncService.backupExcludedPreferenceKeys`의 7개 키를 export/import에서 제외. 기존 설치 덮어쓰기에서는 현재 값을 보존. 복원 완료 뒤 `onRestoreCompleted(restoredSchedule)` 호출 | 백업 snapshot 필터, 복원 prefs 적용 전/후 | 미연결 시 #25 위반 및 복원 후 서버 데이터가 최신 schedule로 dirty 재업로드되지 않음 | G4 대상(T18) — T10 반영 없음 |
| G2-04 | G5 개인정보 ko/en ARB·화면 | 기존 문구가 ownerName 저장을 누락하고 중지 즉시 서버 삭제 완료라고 단정 | ownerName 전송, stop_pending/재시도, 친구 기기 캐시, 익명 UID 재설치 한계를 T22 초안과 맞춰 반영 | G5 개인정보 안내 반영 | 현재 문구와 실제 pending 동작 불일치 | G5 대상(T21/T22) — T10 반영 없음 |

## 후속 결정 대기 (T16)

- D7: 이번 T07에서는 앱 측 `off/active/stop_pending`, dirty, generation과 `revoked` 읽기 호환만 구현했다. `firestore.rules` 변경, tombstone 쓰기, 웹 배포는 하지 않았다. S9 후 사용자 선택 시 G2를 CODING으로 되돌려 rules·앱 stop 제출·웹뷰어를 함께 변경한다.
- D8: 코드 정적 조사상 Android prod/dev 패키지는 `google-services.json`의 서로 다른 app id이지만 같은 project `shiftbell-29f31`이고, `initFirebase()`는 `DefaultFirebaseOptions.currentPlatform`의 Android prod app id `...05c0a871...`를 명시한다. 빌드/실행 없이 실제 선택값을 확정하지 않는다. S12에서 dev/prod 각각 `Firebase.app().options.appId/projectId`와 DebugView 목적지를 기록한 뒤 사용자에게 프로젝트 분리 선택을 요청한다.
