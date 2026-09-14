# G4 handoff

```text
그룹 / 담당 / worktree / branch: G4 / Claude (사용자 지시 2026-09-14 "남은 코드 전부 Claude") / worktree 없음 - T17 통합 뒤 dev에서 직접 / dev
공통 기준 SHA / 최종 소스 SHA: T17 통합 cb017cb (G1 4771493 + G2 0cbe392 + G3 98c4831) / 1c5d403
상태: CODE_FROZEN (구현만. 사용자 지시로 G4 전용 테스트 T19 보류 - 컴파일·기존 자동 테스트 회귀만 확인)
수정한 감사 번호: #2(C02+M10) #9(H05+H06) #18(M11) #19(H17) #25(H14 완화) #17 백업 부분(확인만 - 파일명 이미 Locale.US, Dart 날짜 ISO). 연결 요청 G2-03, G3 #2 반영
실제 변경 파일:
  Dart 신규 - lib/services/backup_policy.dart, backup_validator.dart, restore_coordinator.dart, lib/screens/restore_interrupted_screen.dart
  Dart 수정 - lib/models/backup_payload.dart(schemaVersion 2), lib/services/backup_service.dart(export만), backup_watcher.dart, lib/screens/restore_backup_screen.dart, settings_tab.dart(복원 흐름), lib/main.dart(InitialRouter 중단 복원 확인), lib/providers/schedule_provider.dart(_loadSchedule mounted 확인 - T17 통합 회귀), ARB ko/en 9키
  Kotlin 신규 - RestoreGate.kt(잠금·재생 설정 스냅샷), RestoreOs.kt(이월 확인·OS 정리·재조정)
  Kotlin 수정 - MainActivity.kt(복원 채널 7개, 백업 파일 I/O 백그라운드, IS_PENDING, 최신 유효 후보 탐색), AlarmRefreshEngine.refresh(owner 토큰·잠금), AlarmWakeScheduler(retryFailed 잠금, parse internal), ScheduleNotificationScheduler.rescheduleAllFromDb(owner 토큰·잠금), SleepDetectionReceiver.checkNow·SleepWidgetActionReceiver(잠금), AlarmPlayer.playAlarmFromDB·CustomAlarmReceiver.getDurationFromDB(스냅샷 우선), AlarmActionHelper.dismiss(스냅샷 정리)
공통 파일/API/ARB 연결 요청 및 반영 SHA: G2-03(공유 7키 export/import 제외 + onRestoreCompleted) 1c5d403, G3 #2(수면 DB writer·감지 예약 복원 중 연기) 1c5d403
사용자 결정 확인: D5(snoozed 백업 제외) 적용, D9(암호화 대신 안내 - G5 문구) 적용. AI 위임 결정은 docs/release_audit/decisions_delegated_2026-09-14.md
최종 동작과 회귀 금지 규칙 준수:
  - 이력(alarm_history/alarm_creation_log) 비우기·자동 삭제 없음 - 복원은 자연키 중복 제외 병합
  - 알람 재생·끄기·스누즈·타임아웃은 복원 잠금과 무관하게 동작, 진행 중 알람 ID 불변(충돌 시 백업 custom이 새 ID)
  - DB 스키마 v24 무변경, 새 prefs는 Native DP prefs "restore_state"(잠금 토큰·중단 플래그·재생 스냅샷)만 - contracts §7.2 등록 필요(아래)
  - 검증 실패·사본 저장 실패면 DB/설정/OS 무변경
추가/변경 테스트와 실제 실행 명령: G4 전용 테스트 없음(T19 보류). 회귀 확인만 - flutter build apk --flavor dev --debug, flutter test 전체, gradlew testDevDebugUnitTest (flutter build apk --flavor dev --debug PASS, flutter test 252/252 PASS, gradlew testDevDebugUnitTest 71/71 PASS (2026-09-14, dev 통합본))
미실행 실기기/Console 항목: S5 S6 S17 V2 V3 전체 - docs/release_audit/g6/device_test_plan.md 세션 C
잔여 위험·다음 그룹 주의사항:
  1. G4 코드는 실제 복원 경로를 한 번도 실행하지 않았음(T19·세션 C 전) - 특히 이월·ID 매핑·중단 재개는 설계 검토만
  2. 단계 기록은 Dart 작업 파일(DP 저장소 restore_work/job.json), 잠금은 네이티브 prefs+메모리 - 단일 프로세스 전제. android:process 추가 시 재설계
  3. prepareCarryOver와 DB 트랜잭션 사이에 새로 스누즈된 알람은 스냅샷이 트랜잭션 재시도 전 다시 찍히지만, 그 짧은 틈의 스누즈가 복원 뒤 새 alarm_types로 울릴 수 있음
  4. 복원 중 수면 위젯 입력은 저장하지 않고 토스트만(입력 유실 - 드묾)
  5. 복원 중단 알림 문구는 네이티브 한국어 하드코딩
  6. 백업은 여전히 평문 파일(D9) - G5 안내로 대응
  7. 오래된 백업(schemaVersion 1)은 custom 알람이 없어 덮어쓰기 복원 시 현재 custom 알람이 사라짐(백업 시점 상태로 교체 원칙) - 확인 화면에 백업 시각만 표시
  8. contracts §7.2 등록 필요 키: DP prefs restore_state.restore_lock_token / restore_interrupted / restore_deferred_writers / ring_snapshot_<id> (G4 소유, 백업 안 됨). Flutter prefs backup_last_content_hash(G4, 백업 제외)
```

## writer 대조 결과 (prep_writer_inventory.md 대비)

| writer | 복원 중 처리 | 구현 위치 |
|---|---|---|
| AlarmRefreshEngine.refresh (앱 재개·부팅·Guard·시간대·강제 갱신·알람 끄기 뒤 트리거) | 연기, owner 토큰만 통과 | `RestoreGate.shouldDefer(context, "refresh", ownerToken)` |
| AlarmWakeScheduler.retryFailed | 연기 | 동일 |
| ScheduleNotificationScheduler.rescheduleAllFromDb (부팅·시간대·탭 동기화) | 연기, owner 토큰만 통과 | 동일 |
| SleepDetectionReceiver.checkNow (20분·9시간 알람, Guard, 앱 재개, 부팅) | 연기 | 동일 |
| SleepWidgetActionReceiver | 입력 무시 + 토스트 | 동일 |
| AlarmActionHelper.dismiss/snooze, CustomAlarmReceiver, AlarmPlayer | **허용** (SQLite 쓰기 잠금으로 복원 트랜잭션과 직렬화, 진행 중 행 원래 ID 이월, 재생 설정 스냅샷) | RestoreOs.prepareCarryOver, restore_coordinator `_replaceInTxn` |
| DirectBootReceiver | 부팅 = 프로세스 재시작 → 죽은 잠금 해제 후 평소대로 | RestoreGate 죽은 잠금 처리 |
| Dart 자동 백업 | 잠금 또는 중단 작업 기록이 있으면 쓰지 않음 | BackupWatcher `_restoreInProgress` |
| Dart UI 쓰기 | 신규 설치 복원 화면·설정 복원 진행 표시 중 조작 불가, 중단 작업은 앱 시작 첫 화면에서 처리 | RestoreBackupScreen, settings_tab, RestoreInterruptedScreen |
| G2 FriendSyncService | 공유 7키 백업 제외, 복원 뒤 onRestoreCompleted | backup_policy, restore_coordinator `_afterUnlock` |
| AlarmGuardReceiver 다음 알람 알림·wakeup 예약, 위젯 갱신 | 읽기·표시만이라 막지 않음(owner 완료 뒤 triggerGuardCheck 재실행) | — |

## 진행 기록

| 일시 | 담당 AI | T | 감사 번호 / 하위 작업 | 커밋 SHA | 다음에 할 일 |
|---|---|---|---|---|---|
| 2026-09-14 | Claude | T17 | G1 4771493 → G2 0cbe392 → G3 98c4831 dev 병합(충돌 0). 통합 테스트에서 G2 F-W02가 ScheduleNotifier 폐기 후 state 대입으로 실패 → `_loadSchedule` mounted 확인 추가 | 890b3cd, (merge g2), cb017cb | G4 |
| 2026-09-14 | Claude | T18 | #2 #9 #18 #19 #25 + G2-03 + G3 #2 구현(위 목록), 테스트 보류(사용자 지시) | 1c5d403 | G5, 세션 C 실기기 |
