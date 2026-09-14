# G4 DB·prefs·OS writer 전수 목록

> **G1 수정 전 초안 — 제품 코드 기준 `c0b2e73`. G1 CODE_FROZEN 뒤 반드시 파일·함수·대상·트리거를 다시 전수 검색하고 이 문서와 차이를 대조한다.**
>
> T07/G2 `5cda0e0`과 T08/G3 `98c4831`은 아직 메인 소스에 통합되지 않았으므로 각 handoff의 writer 목록을 별도 반영했다. 이 문서는 G4 gate 구현 입력이며 CODE_FROZEN이나 테스트 완료 증적이 아니다.

## gate 판정 기준

| 분류 | 복원 중 정책 | 이유 |
|---|---|---|
| 알람 재생·끄기·스누즈·타임아웃 | 허용 | 사용자가 현재 울리는 회차를 제어할 수 있어야 함 |
| 갱신 엔진·Guard 재예약·수면 쓰기·일정 재예약·자동백업·일반 앱 UI 쓰기 | 차단 또는 pending으로 연기 | 복원 중간 DB/prefs를 읽어 OS나 다른 저장소에 확산시키면 안 됨 |
| 복원 owner의 DB/prefs 적용과 최종 OS reconcile | owner token으로만 허용 | 일반 background writer와 구분하여 자기 자신을 막는 교착 방지 |
| DB 마이그레이션/onOpen repair | 복원 시작 전 완료를 선행 조건으로 강제 | 스키마 변경과 데이터 교체를 동시에 수행하지 않음 |

gate 판정은 DP prefs 토큰과 같은 프로세스 메모리 owner 토큰을 함께 사용한다. TTL 경과만으로 살아 있는 owner를 무시하지 않는다. 차단된 트리거는 성공으로 가장하지 말고 재실행 필요 상태를 남긴다.

## SQLite writer — Flutter

| 파일 / 함수군 | 쓰는 테이블 | 주 트리거·컨텍스트 | 복원 중 |
|---|---|---|---|
| `database_service.dart` `_initDatabase`, `_onCreate`, `_onUpgrade`, `DbMigrationRunner` | 전체 스키마, 기본 `alarm_types`, 인덱스, `user_version` | 앱 DB 최초 open/업그레이드, Flutter sqflite worker | 복원 전에 완료; 복원 lock 중 재진입 금지 |
| `DatabaseService.insertAlarmType/deleteAlarmType` | `alarm_types` | 설정 UI | 차단 |
| `insertAlarm`, `updateAlarm`, `deleteAlarm`, `insertAlarmsInBatch`, `deleteAllAlarms*`, `logAlarmCreation` | `alarms`, `alarm_history`, `alarm_creation_log` | 알람 UI, 생성/정리 | 일반 UI·재생성은 차단. 현재 회차 dismiss/snooze는 Native 허용 경로 사용 |
| `saveShiftSchedule/updateShiftSchedule` | `shift_schedule` | 온보딩·근무표/설정 저장 | 차단 |
| `insertAlarmTemplate/deleteAlarmTemplate/replaceAllAlarmTemplates/deleteAllAlarmTemplates` | `shift_alarm_templates` | 온보딩·고정 알람 설정 | 차단 |
| `renameShiftAtomic` | `shift_schedule`, `shift_alarm_templates`, `alarms`, `condition_shift_times` 및 G1 추가 override 연계 | 근무명 변경 UI의 단일 transaction | 차단 |
| `createMemo/updateMemo/deleteMemo/reorderMemos` | `date_memos` | 달력 메모 UI | 차단 |
| `adjustOvertime` | `date_overtime` | 달력 OT 추가·삭제 | 차단 |
| `resetAllAlarmHistoryAndLog` | `alarm_history`, `alarm_creation_log` | 근무표 전체 초기화 | 차단; 복원은 이력을 삭제하지 않고 병합 |
| `insertFriend/updateFriendData/renameFriend/deleteFriend` | `friends` | 친구 추가·서버 refresh·이름 변경·삭제 | 차단/연기 |
| `createSchedule/updateSchedule/deleteSchedule` | `date_schedules` | 일정관리 UI, 알림 toggle 포함 | 차단; OS 일정 예약도 함께 연기 |
| `upsertConditionShiftTime/deleteConditionShiftTime` | `condition_shift_times` | 근무시간 설정 | 차단 |
| `insertSleepRecord/updateSleepRecord/deleteSleepRecord` | `sleep_records` | 수면 UI 및 G3 만료 백스톱 | 차단/연기 |
| `alarm_generation_service.dart` `regenerateFixedAlarmsForDates*` | `alarms`, `alarm_history`, `alarm_creation_log` | 근무 변경 후 fixed diff | 차단; 복원 owner 최종 fixed 재생성만 허용 |
| `alarm_provider.dart` `add/delete/regenerate/deleteAll/updateAlarmType` | 위 알람 3테이블, 직접 `alarms.alarm_type_id` update | 알람 탭·근무 변경·초기화 | 차단 |
| `schedule_provider.dart` `save/update/change/bulk/reset/changeShiftWithAlarms` | `shift_schedule`, `shift_alarm_templates`, 알람 3테이블 | 온보딩·달력·설정 UI | 차단 |
| `settings_tab.dart` `_updateType`, 근무명/색/패턴/고정알람 적용 | `alarm_types`, `shift_schedule`, templates, alarms 및 연계 테이블 | 설정 UI | 차단 |
| `schedule_management_tab.dart` 일정 notifier 저장 및 `_nextEtcIconIndex` | `date_schedules`; Flutter prefs counter | 일정관리 UI | 차단 |
| `backup_service.dart` `restoreAll` | 백업에 포함된 모든 알려진 테이블을 delete/insert | 복원 UI | **owner만 허용**. 현 구현은 전체 검증·단계 재시도·이력 병합 계약 미충족 |
| `db_migration_runner.dart` | 마이그레이션 SQL 대상 전체 | DB open/테스트 주입 | 복원 전에 완료 |

## SQLite writer — Native

| 파일 / 함수군 | 쓰는 테이블 | 주 트리거·컨텍스트 | 복원 중 |
|---|---|---|---|
| `DatabaseHelper.kt`, `DbMigrationRunner.kt` | 스키마·기본값·`user_version` | 앱/Receiver의 첫 DB open, main process | 복원 전에 완료 |
| `AlarmRefreshEngine.refresh/doRefresh` | fixed `alarms` diff, `alarm_history`, `alarm_creation_log` | 앱 resume, boot, Guard, 시간/시간대 변경, 강제 refresh | 차단·pending. owner 최종 reconcile만 허용 |
| `AlarmActionHelper.dismiss` | `alarms` delete, `alarm_history` insert | 울리는 알람 끄기/취소 | **허용**; 현재 회차 ID 보존과 DB 교체 transaction 직렬화 필요 |
| `AlarmActionHelper.snooze` | 같은 `alarms` 행 update, 이력/생성로그 insert | 울리는 알람 스누즈 | **허용**; 원 ID 및 설정 snapshot 보존 |
| `SleepDetectionReceiver.handle/recordRejection` | `sleep_records` insert/update/delete; 아래 수면 prefs | 20분·9시간 감지 알람, boot/Guard/app resume | 차단·pending |
| `SleepWidgetActionReceiver.onReceive/finishOngoing` | `sleep_records` insert/update/delete | 홈 위젯 취침/기상 BroadcastReceiver | 차단 또는 사용자 입력을 pending으로 보존 |

`MainActivity.kt`는 현재 SQLite 행을 직접 쓰지 않고 MethodChannel을 통해 위 writer와 OS 작업을 호출한다. G1 동결 뒤 새 직접 writer가 생겼는지 다시 검색한다.

## Flutter SharedPreferences writer

현재 `BackupService.exportAll/restoreAll`은 Flutter prefs를 전부 export/import한다. 복원 설계에서는 휘발·소유권·튜토리얼 상태를 명시적으로 분류하고, G2의 공유 키는 전부 제외한다.

| 파일 / 키 | 트리거 | 복원 중 / 백업 판정 |
|---|---|---|
| `permission_intro_screen.dart`, `main.dart`, `splash_screen.dart`, `restore_backup_screen.dart` — `permissions_requested` | 권한 안내 완료·복원 후 | 일반 UI writer 차단. 복원 후 false 강제는 owner 단계 |
| `calendar_theme_provider.dart` — `calendar_theme_id` | 테마 변경 | 차단; 사용자 설정 후보 |
| `schedule_background_provider.dart` — `schedule_management_bg_color_index` | 일정 화면 배경 변경 | 차단; 사용자 설정 후보 |
| `tab_visibility_provider.dart` — `schedule_tab_enabled`, `condition_tab_enabled` | 설정 toggle | 차단; 일정 OS 예약과 함께 reconcile |
| `work_hours_settings_provider.dart` — `work_hours_period_mode`, `work_hours_payday_cutoff_day`, `work_hours_cutoff_anchor`, `work_hours_shift_change_as_ot` | 근무시간/OT 설정 저장 | 차단; `work_hours_cutoff_is_period_start`는 legacy 읽기 전용 |
| `all_teams_setup_screen.dart`, `settings_tab.dart` — `all_teams_names`, `all_teams_my_team`, `all_teams_offsets` | 전체 조 설정/초기화 | 차단 |
| `schedule_management_tab.dart` — `schedule_etc_icon_rotation_counter` | 기타 일정 아이콘 배정 | 차단; 휘발 UI 값 여부 결정 필요 |
| `onboarding_info_popups.dart` — 4개 `*_shown` | 안내 표시 | 차단; 복원 포함 여부를 G5와 결정 |
| `update_service.dart` — 업데이트 확인/릴리스노트 4키 | 시작·resume·안내 | 선택 서비스 writer 연기; 기기 로컬 상태로 보존 권장 |
| `backup_watcher.dart` — `backup_last_data_version`, `backup_last_saved_at` | 백업 파일 성공 뒤 | 자동백업 전체를 차단. 내용 hash 기반 상태로 G4 재설계; 백업 payload 제외 |
| G2 `FriendSyncService` — 기존 2키 + `friend_share_intent/dirty/generation/desired_fingerprint/confirmed_fingerprint` | 공유 시작·수정·중지·늦은 ACK·retry | 차단/연기. **7키 모두 backup export/import 제외**, 기존 설치 현재 상태 유지 |
| `backup_service.dart` `restoreAll` | payload prefs 적용 | owner만 허용; 타입/허용 키 검증 뒤 단계별 적용 |

## Native prefs, OS, 파일, 원격 writer

| 파일 / 함수군 | 대상 | 트리거·컨텍스트 | 복원 중 |
|---|---|---|---|
| `AlarmRefreshEngine`, `AlarmRefreshUtil`, `DirectBootReceiver`, `MainActivity`, `RefreshLockManager`, `RingingAlarmTracker` | DP prefs `alarm_state`: refresh/boot/lock/current ring 및 G1 신규 키 | refresh·boot·울림·MethodChannel | 현재 회차 tracker와 사용자 제어는 허용, refresh 상태는 차단. 복원 owner 토큰은 별도 의미로 구현 |
| `SleepDetectionReceiver` | DP prefs `sleep_detection_state`: `first_off_sample_at`, `reject_hour_*` | 감지·사용자 거부 | 차단/연기; 백업 안 함 |
| `MainActivity.writeBackupFile/cleanupOldBackupFiles` | 일반 prefs `backup_prefs.last_backup_uri`, MediaStore Downloads JSON | 자동/수동 백업 MethodChannel | 자동백업 차단. temp→완성본 공개→성공 상태 기록→옛 파일 정리 순서 |
| `AlarmService`/`MainActivity.scheduleNativeAlarm`, `AlarmRefreshEngine`, `AlarmActionHelper`, `DirectBootReceiver` | AlarmManager 기상 알람 PendingIntent | 생성·refresh·boot·snooze | refresh/일반 예약 차단; 현재 snooze는 허용; owner 최종 fixed/custom/snoozed 명시 재예약 |
| `AlarmGuardReceiver`/`MainActivity.scheduleGuardWakeup` | AlarmManager Guard, 20분 전 Notification | 시작·resume·시간 변경·알람 변화 | 차단/연기; 최종 reconcile 후 1개 재예약 |
| `ScheduleNotificationScheduler` | AlarmManager 일정 알림 + 표시 Notification 취소 | 일정 CRUD/toggle, boot | 차단/연기; 복원된 toggle/시간으로 최종 재예약 |
| G3 `SleepDetectionScheduler` | AlarmManager 수면 감지, 진행 행 start+9h 예약 | 감지 결과·boot·resume | 차단/연기; 복원된 진행 행 기준 재예약 |
| `CustomAlarmReceiver`, `AlarmOverlayService`, `AlarmActivity`, `NotificationHelper` | foreground service, 오버레이, Notification, 진동/소리 | 알람 울림·끄기·스누즈·타임아웃 | 사용자 제어/재생은 허용. 복원 때문에 현재 울림을 끄지 않음 |
| `CalendarWidgetProvider`, `SleepWidgetProvider`, `WidgetRefreshService` | AppWidget RemoteViews | 일정/메모/수면 변경, launcher update | DB write 없음. 복원 완료 후 refresh; 중간 상태 refresh 연기 |
| G2 `FriendSyncService` | Firebase Auth 익명 UID, Firestore `friend_schedules/{uid}` set/delete | 공유 UI·schedule commit·lifecycle retry | 차단/dirty 유지; owner 최종 restore callback에서 현재 상태만 재제출 |

## G1 동결 뒤 재대조 절차

1. G1 handoff의 변경 파일과 writer 목록을 이 문서에 합친다.
2. Dart에서 SQLite write, SharedPreferences setter/remove, MethodChannel OS 변경 호출을 다시 검색한다.
3. Kotlin에서 SQLite write, prefs edit, AlarmManager/Notification/MediaStore writer를 다시 검색한다.
4. 모든 writer에 파일·함수·대상·트리거·실행 컨텍스트·gate 정책이 있는지 대조한다.
5. G2/G3 통합 SHA에서 handoff 목록이 실제 코드와 일치하는지 확인한다.
6. 누락 0을 확인하기 전 G4 복원 구현을 CODE_FROZEN으로 표시하지 않는다.
