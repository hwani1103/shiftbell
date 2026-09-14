# 전체 앱 코드 품질 점검 (사용자 체감 버그 중심) — 2026-09-15

- 기준: `dev` (ab23fdf 이후), 배포분과의 차이가 아니라 **앱 전체**를 다시 읽음
- 초점: 실제 사용자에게 일어날 수 있는 버그. 스타일·리팩터링 제안은 제외
- 방법: 코드 읽기만(실기기 재현 없음). 등급은 "사용자가 겪을 가능성 × 피해" 기준

## 읽은 범위

- Dart: 모델 전체(shift_schedule, alarm, date_schedule, shift_time_range, sleep_record, friend_schedule), 주요 provider 전부
  (alarm, schedule, date_schedule, memo, overtime, sleep_record, condition*, work_hours_settings, tab_visibility, friend),
  서비스(alarm_generation, alarm_service, alarm_refresh, database_service, schedule_notification, update_service, work_hours_calculator,
  condition/sleep_opportunity, shift_pattern_analyzer), 화면(main, startup_gate, onboarding, calendar_tab 알람·일괄변경 구간,
  settings_tab 백업·템플릿·소리 구간, next_alarm_tab, schedule_management_tab 초기화·저장 구간, all_teams_setup, all_shifts_view,
  work_hours_settings, permission_intro, condition_tab, memo_list_view, sleep_edit_dialog, sleep_calendar_full_screen, friend_list),
  위젯(permission_warning_banner, disable_tab_button), holiday_util
- Kotlin: MainActivity 전체, DatabaseHelper, AlarmRefreshEngine, AlarmRefreshUtil, RefreshLockManager, AlarmRefreshReceiver,
  ScheduleNotificationScheduler/Receiver, CustomAlarmReceiver, AlarmActivity, AlarmOverlayService, AlarmPlayer, AlarmGuardReceiver,
  SleepDetectionScheduler/Receiver, SleepScheduleResolver, SleepWidget*, CalendarWidget*, DirectBootReceiver(일부)
- 이전 세션(R-01~R-07, X-01~X-14)에서 이미 본 복원·백업·울림 경로는 다시 지적하지 않음

## 결과 요약

| ID | 등급 | 내용 | 조치 |
|----|------|------|------|
| Q-01 | Medium | 온보딩 "시작하기" 연타 시 스케줄·템플릿·알람 중복 저장 | **수정** |
| Q-02 | Medium | 달력 다중선택 → 근무 일괄 변경: 시트/진행 다이얼로그 pop 순서 역전 | **수정** |
| Q-03 | Low-Medium | 알람음 미리듣기 후 시스템 알람 볼륨 50%가 복원 안 된 채 남을 수 있음 | **수정** |
| Q-04 | Low | 미리듣기 볼륨이 최대 1단계 기기에서 0(무음) | **수정**(Q-03과 같이) |
| Q-05 | Low | `cancelAlarmGuard` requestCode(999999)가 실제 예약(0)과 달라 취소가 안 됨 | 보류(무해) |
| Q-06 | Low | 날짜 상세 팝업이 `ref.invalidate(alarmNotifierProvider)` — 진행 중 작업이 있으면 dispose 후 사용 가능성 | 보류 |
| Q-07 | Low | `sleep_records` 한 행의 날짜가 깨지면 `DateTime.parse` 예외로 수면 목록 전체 로드 실패 | 보류 |
| Q-08 | Low | 설정 알람 템플릿 저장(`_saveAndExit`)에서 `replaceAllAlarmTemplates` 예외 시 사용자 안내 없음 | 보류 |
| Q-09 | Low | 업데이트 안내 다이얼로그 제목 Row에 Expanded 없음 — 긴 영어 문구·큰 글꼴에서 overflow 가능 | 보류 |
| Q-10 | Low | AlarmGuardReceiver `shownNotifications`가 메모리 전용 — 프로세스가 죽으면 20분 전 알림이 다시 뜰 수 있음 | 보류 |
| Q-11 | Info | 친구 추가 다이얼로그 TextEditingController 미해제, 추가 버튼 연타 가드 없음(중복은 provider가 거부) | 보류 |

## 상세

### Q-01 (Medium, 수정) 온보딩 저장 연타
- 위치: `lib/screens/onboarding_screen.dart` `_buildComplete` → `AppButton(onPressed: _saveAndFinish)`
- 문제: `_saveAndFinish`는 스케줄 저장 → 템플릿 insert → 기존 알람 삭제 → 10일치 생성 → 화면 교체까지 수백 ms~수 초 걸리는데
  진행 중 가드가 없었음. `saveSchedule`은 id 없는 스케줄을 **insert**, `insertAlarmTemplate`은 **append**라서 두 번째 탭이
  같은 작업을 겹쳐 실행하면 `shift_schedule` 행 2개, 근무별 템플릿 2배(최대 5개 제한도 우회), 알람·OS 예약 중복이 생길 수 있음.
  반응이 느린 저가 기기에서 "안 눌린 줄 알고 한 번 더" 누르는 흔한 상황.
- 수정: `_finishing` 플래그 — 진행 중엔 버튼 비활성·재진입 무시, 성공하면 화면이 교체되므로 그대로 두고 **실패했을 때만** 다시 풀어줌.

### Q-02 (Medium, 수정) 근무 일괄 변경 시트
- 위치: `lib/screens/calendar_tab.dart` `_showBulkAssignSheet` 버튼 `onPressed`
- 문제: `_bulkAssignShift(...)` 호출 뒤 `Navigator.pop(context)` 순서였음. `_bulkAssignShift`는 첫 `await` 전에 `showDialog`로
  진행 표시를 **동기로 push**하므로, 바로 뒤의 pop이 시트가 아니라 방금 뜬 진행 다이얼로그를 닫음.
  결과: 진행 표시가 안 보이고 시트가 작업 내내 열린 채 남음 → 작업 끝의 `Navigator.pop`이 그제서야 시트를 닫음.
  그 사이 사용자가 다른 근무 버튼을 한 번 더 누르면 pop이 한 번 더 늘어나 **메인 화면 라우트까지 닫혀 검은 화면**이 될 수 있고,
  두 일괄 변경이 겹쳐 실행됨.
- 수정: 시트를 먼저 닫고 `_bulkAssignShift` 시작.

### Q-03 / Q-04 (Low-Medium, 수정) 알람음 미리듣기 볼륨
- 위치: `MainActivity.kt` `playPreviewSound` / `stopPreviewSound` / `onDestroy`
- 문제: 미리듣기는 시스템 `STREAM_ALARM` 볼륨을 50%로 바꾸고 `stopPreviewSound`에서만 복원함. 복원은 Dart 설정 화면의 정지 버튼·dispose에서만 불려서,
  (a) 재생이 끝나도 화면을 나갈 때까지 50% 유지, (b) 미리듣기 도중 홈으로 나가 최근 앱에서 종료하면 **복원이 영영 안 됨** →
  삼성 시계 등 **다른 알람 앱의 음량이 사용자가 모르게 바뀜**(이 앱의 알람은 AlarmPlayer가 매번 50%로 맞추므로 영향 없음).
  또 `maxVolume / 2`가 최대 1단계 기기에서 0이라 미리듣기가 무음(AlarmPlayer는 2026-09-04에 이미 `coerceAtLeast(1)`로 고침).
- 수정: 재생 완료 리스너와 `onDestroy`에서 `stopPreviewSound()` 호출, `halfVolume.coerceAtLeast(1)`.
- 남는 한계: 프로세스가 강제로 죽는 경우(onDestroy 미호출)는 여전히 복원 불가.

### Q-05 (Low, 보류) Guard 취소 requestCode 불일치
- `MainActivity` `cancelAlarmGuard`는 requestCode 999999로 PendingIntent를 만들지만, 실제 예약(`scheduleGuardWakeup`, AlarmGuardReceiver 자기 재예약)은 0.
  그래서 초기화·전체 삭제 때 Guard 하트비트가 취소되지 않음. Guard는 스케줄이 없으면 할 일이 없어 **사용자 영향 없음**.
  고치면 초기화 직후 앱 재시작 전까지 Guard가 멈추는 새로운 경로가 생기므로 이번엔 건드리지 않음.

### Q-06 (Low, 보류) 날짜 상세 팝업의 provider invalidate
- `calendar_tab.dart` `_showDayDetailPopup`에서 `ref.invalidate(alarmNotifierProvider)` — 기존 notifier를 dispose하고 새로 만듦.
  같은 순간 다른 곳에서 그 notifier의 비동기 메서드(재생성 등)가 진행 중이면 dispose 뒤 `state =` 대입 예외 가능. 타이밍이 매우 좁음.

### Q-07 (Low, 보류) 수면 기록 한 행 손상 시 전체 실패
- `sleep_record.dart` `fromMap`이 `DateTime.parse` 예외를 그대로 던져, 행 하나가 깨지면 컨디션 탭 수면 카드·전체보기가 통째로 로드 실패.
  정상 경로(Dart·Native 모두 같은 형식으로 씀)에서는 손상 행이 생기지 않고, 복원은 `BackupValidator`가 형식을 검사하므로 가능성 낮음.

### Q-08 (Low, 보류) 알람 템플릿 저장 실패 무안내
- `settings_tab.dart` `_saveAndExit`에서 `replaceAllAlarmTemplates` 예외가 사용자 메시지 없이 끝남(화면은 그대로). 디스크 부족 등 드문 상황.

### Q-09 (Low, 보류) 업데이트 안내 다이얼로그 제목 overflow
- `update_service.dart` 다이얼로그 제목 `Row(아이콘, Text)`에 `Expanded`/`Flexible` 없음. 영어 + 시스템 큰 글꼴에서 노란 줄무늬(release는 잘림).

### Q-10 (Low, 보류) 20분 전 알림 중복 표시
- `AlarmGuardReceiver.shownNotifications`는 메모리 Set — 프로세스 재시작 후 같은 알람의 20분 전 알림이 다시 뜰 수 있음(같은 ID라 알림이 겹치진 않고 다시 울림).

### Q-11 (Info)
- `friend_list_screen.dart` 친구 추가 다이얼로그: 컨트롤러 미해제(작은 누수), 추가 버튼 연타 시 `addFriend` 중복 호출 — 두 번째는 중복으로 거부되어
  "잘못된 코드 또는 이미 추가됨" 스낵바가 한 번 더 뜰 수 있음.

## 문제없음으로 확인한 곳 (다시 볼 필요 없음)
- `startup_gate.dart`: 실패·정지 시 재시도, 옛 시도 결과 무시 — 정상
- `DatabaseHelper.kt`: 게이트(파일 없음/0/다운그레이드) + onUpgrade 잠금 안 재확인 + repair — 정상
- `sleep_opportunity.dart` ↔ `SleepDetectionScheduler.kt`: 활성 창 우선·9시간 캡·진행 중 AUTO 기한 — 정상
- `shift_pattern_analyzer.dart`: 연속 일수 루프 180일 캡 — 정상
- `holiday_util.dart` ↔ `CalendarWidgetHolidays.kt`: 2025~2029 날짜 집합 일치
- `permission_warning_banner.dart`, `disable_tab_button.dart`, `sleep_calendar_full_screen.dart`: 사용자 영향 버그 없음

## 검증
- `flutter analyze` (변경 파일): 새 issue 없음
- `flutter test`: 259/259 통과
- Kotlin 변경(MainActivity 미리듣기)은 dev release APK 빌드로 컴파일 확인
- 실기기 확인 권장: 온보딩 "시작하기" 빠르게 두 번 탭 → 설정 알람 템플릿 개수 정상, 달력 다중선택 → 근무 일괄 변경 시 시트가 즉시 닫히고 진행 표시가 보임,
  알람음 미리듣기 재생 후 끝까지 두고 기기 알람 볼륨이 원래대로인지
