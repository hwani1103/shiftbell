# ShiftBell 테스트 체크리스트

## 카테고리 1: 온보딩 / 달력 / 근무 / 메모 / 전체근무표

### 1.1 온보딩 - 규칙적 스케줄
- [ ] 규칙적 선택 → 근무 형태 생성 → 패턴 입력 → 오늘 인덱스 선택 → 알람 설정 → 완료
- [ ] 기본 근무 형태 5개 표시 확인 (주간, 야간, 오전, 오후, 휴무)
- [ ] 커스텀 근무 추가 (최대 4개) - 5번째 추가 시 버튼 비활성화 확인
- [ ] 커스텀 근무명 4글자 제한 확인
- [ ] 커스텀 근무 삭제 시 패턴에서도 제거되는지 확인
- [ ] 패턴 입력 (최대 30일) - 31번째 입력 시 버튼 비활성화 확인
- [ ] 패턴 셀 탭하여 삭제 기능 확인
- [ ] 오늘 인덱스 미선택 시 "다음" 버튼 비활성화 확인
- [ ] 각 근무당 알람 템플릿 최대 3개 설정 확인
- [ ] 알람 템플릿 시간 수정 기능 확인
- [ ] 알람 타입 선택 (소리/진동/무음) 확인
- [ ] 완료 후 10일치 알람 자동 생성 확인
- [ ] 뒤로가기 시 상태 초기화 확인

### 1.2 온보딩 - 불규칙 스케줄
- [ ] 불규칙 선택 → 근무 형태 확인 → 실제 사용 근무 선택 → 알람 설정 → 완료
- [ ] 근무 선택 안 하면 "다음" 버튼 비활성화 확인
- [ ] 선택한 근무에 대해서만 알람 템플릿 설정 화면 표시 확인
- [ ] 불규칙 모드에서는 자동 알람 생성 안 됨 확인

### 1.3 달력 기능
- [ ] 월별 달력 표시 및 스와이프로 월 이동
- [ ] "today" 버튼으로 오늘 날짜로 이동
- [ ] 날짜 탭 → 상세 팝업 표시 (근무 타입, 알람 목록, 메모)
- [ ] 이전/다음 달 날짜 탭 무시되는지 확인
- [ ] 날짜 길게 누르기 → 다중 선택 모드 진입
- [ ] 다중 선택 모드에서 여러 날짜 선택 후 일괄 근무 변경
- [ ] 근무 색상이 달력에 제대로 표시되는지 확인
- [ ] 휴무는 진한 빨강색으로 표시되는지 확인
- [ ] 오늘 날짜에 border 표시 확인

### 1.4 근무 변경 기능
- [ ] 날짜 팝업에서 근무 타입 변경 → 해당 날짜 알람 즉시 재생성 확인
- [ ] 다중 선택 후 일괄 근무 변경 → 모든 선택 날짜 알람 재생성 확인
- [ ] 근무 변경 후 달력 색상 즉시 업데이트 확인
- [ ] 변경된 알람이 "다음 알람" 탭에 즉시 반영되는지 확인
- [ ] 과거 날짜 근무 변경 시 알람 생성 안 됨 확인

### 1.5 메모 기능
- [ ] 날짜별 메모 생성 (최대 3개)
- [ ] 4번째 메모 추가 시 에러 메시지 또는 버튼 비활성화
- [ ] 메모 수정 기능
- [ ] 메모 삭제 기능
- [ ] 메모 순서 변경 (드래그)
- [ ] 메모 있는 날짜에 아이콘 표시 확인
- [ ] 빈 메모 저장 방지 확인

### 1.6 전체 근무표
- [ ] "전체근무표" 버튼 탭 → 전체 근무표 화면 이동
- [ ] 미설정 상태일 때 안내 메시지 표시
- [ ] 설정 후 월별 페이지 스와이프로 이동
- [ ] 좌우 화살표로 월 이동
- [ ] 오늘 날짜에 하이라이트 표시
- [ ] 각 조(A, B, C, D)의 근무가 정확히 계산되어 표시되는지 확인
- [ ] 근무명이 2글자로 축약 표시되는지 확인
- [ ] 색상이 달력과 동일하게 표시되는지 확인

### 1.7 설정 화면 - 교대근무 초기화
- [ ] "교대근무 초기화" 버튼 → 확인 다이얼로그 표시
- [ ] 초기화 실행 → 모든 알람 취소 + DB 삭제 + 온보딩 화면 이동
- [ ] 초기화 시 전체 교대조 근무표 데이터도 삭제되는지 확인
- [ ] 초기화 후 알람 이력은 남아있는지 확인

---

## 카테고리 2: DB 알람 동기화 & Notification 정확도

### 2.1 알람 생성 동기화
- [ ] **Flutter에서 알람 생성 시:**
  - DB에 알람 저장 → DB ID 획득 → Native 알람 등록 (DB ID 사용)
  - "등록된 알람" 목록에 즉시 표시
  - AlarmGuardReceiver 트리거 → 20분 이내면 Notification(8888) 표시
- [ ] **근무 변경 시 알람 재생성:**
  - 기존 알람 Native 취소 → DB 삭제 → 새 알람 DB 저장 → Native 등록
  - 목록에 즉시 반영
- [ ] **과거 시간 알람은 생성 안 됨** (1분 이상 지난 시간)

### 2.2 알람 삭제 동기화
- [ ] **Flutter에서 알람 삭제 시:**
  - DB에서 삭제 → Native 알람 취소 → Notification(8888, 8889) 삭제
  - shownNotifications 정리 (유령 Notification 방지)
  - 목록에서 즉시 제거
- [ ] **교대근무 초기화 시:**
  - 모든 알람 Native 취소 → DB 삭제 → 모든 Notification 삭제
  - shownNotifications 전체 초기화
  - AlarmGuardReceiver 취소
- [ ] **근무 변경으로 알람 삭제 시:**
  - 위와 동일한 프로세스

### 2.3 Notification 동기화 (8888: 20분 전 알림)
- [ ] **20분 이내 알람 있을 때 8888 Notification 표시**
- [ ] **Notification 표시 후 shownNotifications에 기록**
- [ ] **같은 알람 ID에 대해 중복 Notification 안 뜸**
- [ ] **알람 삭제 시 8888 Notification도 즉시 삭제**
- [ ] **알람 끄기 버튼 → 알람 삭제 + 8888 삭제**
- [ ] **5분 후 버튼 → 알람 스누즈 + 8888 삭제 + 새 알람 생성 + 새 8888 표시 (20분 이내면)**

### 2.4 Notification 동기화 (8889: 스누즈 결과)
- [ ] **스누즈 실행 시 8889 Notification 표시** ("XX:XX로 연장되었습니다")
- [ ] **30초 후 8889 자동 삭제**
- [ ] **스누즈 후 다음 알람이 20분 이내면 새 8888 표시**

### 2.5 유령 알람 방지
- [ ] **DB에 있는 알람 = Native에 등록된 알람** (100% 일치)
- [ ] **DB에서 삭제된 알람은 Native에서도 즉시 취소됨**
- [ ] **재부팅 시 Native 알람 날아감 → DirectBootReceiver가 다음 1개 재등록**
- [ ] **AlarmGuardReceiver가 누락 알람 감지 → 자동 재등록**

### 2.6 유령 Notification 방지
- [ ] **알람 삭제 시 cancelNotification 호출 → 8888, 8889 삭제**
- [ ] **알람 삭제 시 clearShownNotifications 호출 → 이력 초기화**
- [ ] **교대근무 초기화 시 cancelAllNotifications + clearShownNotifications**
- [ ] **모든 알람 삭제 시 cancelAllNotifications + clearShownNotifications**
- [ ] **스누즈 시 8888 삭제 → 8889 표시 → 30초 후 8889 자동 삭제**

### 2.7 알람 울림 → 끄기 (Dismiss)
- [ ] **잠금 화면: AlarmActivity 표시**
  - 끄기 버튼 → 소리 중지 → Native 알람 취소 → DB 삭제 → 이력 기록(dismissed) → Activity 종료
  - AlarmGuardReceiver 트리거 → 다음 알람 8888 표시
- [ ] **해제 화면: AlarmOverlayService 표시**
  - 끄기 버튼 → 소리 중지 → Native 알람 취소 → DB 삭제 → 이력 기록(dismissed) → Overlay 제거
  - AlarmGuardReceiver 트리거 → 다음 알람 8888 표시
- [ ] **"다음 알람" 탭에서 끄기 버튼:**
  - DB 삭제 → Native 취소 → Notification 삭제 → UI 즉시 갱신
  - AlarmGuardReceiver 트리거

### 2.8 알람 울림 → 타임아웃
- [ ] **AlarmActivity 타임아웃 (1분):**
  - 소리 중지 → Native 알람 취소 → DB 삭제 → 이력 기록(timeout) → Activity 종료
  - AlarmGuardReceiver 트리거
- [ ] **AlarmOverlayService 타임아웃 (1분):**
  - 소리 중지 → Native 알람 취소 → DB 삭제 → 이력 기록(timeout) → Overlay 제거
  - AlarmGuardReceiver 트리거
- [ ] **타임아웃 시간은 DB의 alarm_types.duration 값 사용** (현재 테스트용 1분)

### 2.9 알람 울림 → 스누즈
- [ ] **AlarmActivity 스누즈:**
  - 소리 중지 → 기존 알람 DB 삭제 + Native 취소 → 이력 기록(snoozed)
  - 5분 후 새 알람 DB 저장 + Native 등록 → Activity 종료
  - 8888 삭제 → 8889 표시 → 30초 후 8889 자동 삭제
  - AlarmGuardReceiver 트리거 → 새 알람이 20분 이내면 새 8888 표시
- [ ] **AlarmOverlayService 스누즈:**
  - 위와 동일
- [ ] **Notification(8888) 스누즈 버튼:**
  - 기존 알람 DB 삭제 + Native 취소 → 이력 기록(snoozed)
  - 5분 후 새 알람 DB 저장 + Native 등록
  - 8888 삭제 → 8889 표시 → AlarmGuardReceiver 트리거

### 2.10 Notification 버튼 동작
- [ ] **8888 Notification "끄기" 버튼:**
  - 알람 DB 삭제 + Native 취소 → 이력 기록(cancelled)
  - 8888 삭제 → shownNotifications 정리
  - AlarmGuardReceiver 트리거
- [ ] **8888 Notification "5분 후" 버튼:**
  - 스누즈와 동일한 프로세스
- [ ] **Notification 탭 시 앱 열기 (MainActivity, 다음 알람 탭으로 이동)**

### 2.11 Edge Cases - 동시성
- [ ] **알람이 울리는 동안 Flutter에서 삭제 시:**
  - Flutter: DB 삭제 + Native 취소 + Notification 삭제
  - AlarmActivity/Overlay: dismissAlarmFromExternal로 UI만 정리
  - 중복 작업 없음
- [ ] **알람이 울리는 동안 다른 앱에서 시스템 알람 조작 시:**
  - AlarmGuardReceiver가 누락 감지 → 재등록
- [ ] **네트워크 없이도 모든 기능 동작 (로컬 DB + Native API)**

---

## 카테고리 3: 알람 갱신 시스템

### 3.1 자동 갱신 트리거
- [ ] **앱 시작 시:** `AlarmRefreshService.refreshIfNeeded()` 호출
- [ ] **자정 넘어갈 때:** AlarmGuardReceiver → AlarmRefreshUtil → AlarmRefreshReceiver
- [ ] **알람 울릴 때:** CustomAlarmReceiver → AlarmRefreshUtil
- [ ] **앱 포그라운드 진입 시:** main.dart didChangeAppLifecycleState

### 3.2 갱신 로직 (규칙적 스케줄만)
- [ ] **하루에 한 번만 갱신** (SharedPreferences에 날짜 저장)
- [ ] **같은 날짜면 스킵**
- [ ] **다음 날이면 갱신 실행:**
  1. 기존 알람 전부 Native 취소 + DB 삭제
  2. 10일치 알람 재생성 (오늘부터 +9일)
  3. SharedPreferences에 갱신 날짜 저장
  4. AlarmGuardReceiver 트리거

### 3.3 AlarmRefreshReceiver 동작
- [ ] **자정 또는 날짜 변경 시 트리거됨**
- [ ] **불규칙 스케줄이면 스킵**
- [ ] **규칙적 스케줄이면 10일치 재생성**
- [ ] **10일 이상 지난 알람 이력 자동 삭제**
- [ ] **갱신 완료 후 Flutter UI 갱신 트리거 (앱 켜져있으면)**

### 3.4 재부팅 대응
- [ ] **재부팅 시 Native 알람 모두 날아감**
- [ ] **DirectBootReceiver (LOCKED_BOOT_COMPLETED):**
  1. DB에서 다음 알람 1개 조회
  2. 해당 알람만 Native 재등록
  3. AlarmGuardReceiver 자정 예약
  4. SharedPreferences 갱신 플래그 리셋 (last_alarm_refresh = 0)
- [ ] **해당 알람이 울리면 CustomAlarmReceiver → AlarmRefreshUtil → 10일치 재생성**
- [ ] **또는 자정 되면 AlarmGuardReceiver → AlarmRefreshUtil → 10일치 재생성**

### 3.5 AlarmGuardReceiver
- [ ] **자정 또는 다음 알람 20분 전에 wakeup**
- [ ] **깨어나면:**
  1. AlarmRefreshUtil로 갱신 체크 & 실행
  2. 다음 알람 조회
  3. 20분 이내면 Notification(8888) 표시
  4. Native 알람 등록 여부 체크 → 누락이면 재등록
  5. 다음 wakeup 예약 (자정 또는 20분 전 중 빠른 것)

### 3.6 Edge Cases
- [ ] **앱을 10일 이상 안 켜도 알람 계속 울림:**
  - 매일 자정 AlarmGuardReceiver → AlarmRefreshUtil → 10일치 갱신
- [ ] **재부팅 직후 첫 알람이 울리면 나머지도 자동 갱신됨**
- [ ] **갱신 중 앱 종료되어도 다음 자정에 다시 갱신**
- [ ] **규칙적 → 불규칙 전환 시 갱신 중단**
- [ ] **불규칙 → 규칙적 전환 시 갱신 재개**

### 3.7 Device Protected Storage
- [ ] **alarm_state (Native)와 Flutter SharedPreferences는 다른 경로**
- [ ] **재부팅 후에도 alarm_state 접근 가능 (Device Protected Storage)**
- [ ] **갱신 플래그는 alarm_state에 저장되어 있음**

---

## 카테고리 4: 알람 이력 시스템

### 4.1 이력 기록 시점
- [ ] **알람 울림 시:** CustomAlarmReceiver → 즉시 'ringing' 기록
- [ ] **끄기:** AlarmActivity/Overlay dismissAlarm → 'dismissed' 기록 (기존 ringing 업데이트)
- [ ] **타임아웃:** AlarmActivity/Overlay timeoutAlarm → 'timeout' 기록 (기존 ringing 업데이트)
- [ ] **스누즈:** AlarmActivity/Overlay snoozeAlarm → 'snoozed' 기록 (기존 ringing 업데이트)
- [ ] **Notification 끄기:** AlarmActionReceiver CANCEL_ALARM → 'cancelled' 기록
- [ ] **교대근무 초기화:** resetSchedule → 모든 알람 'deleted_by_user' 기록

### 4.2 이력 필수 정보
- [ ] **alarm_id:** DB ID
- [ ] **scheduled_time:** 예정 시간 (HH:mm)
- [ ] **scheduled_date:** 예정 날짜 (yyyy-MM-dd'T'HH:mm:ss)
- [ ] **actual_ring_time:** 실제 울린 시간
- [ ] **dismiss_type:** 처리 방식 (ringing/dismissed/timeout/snoozed/cancelled/deleted_by_user)
- [ ] **snooze_count:** 스누즈 횟수
- [ ] **shift_type:** 근무 타입
- [ ] **created_at:** 이력 생성 시간

### 4.3 스누즈 이력
- [ ] **스누즈 시:**
  1. 기존 알람 이력 업데이트 (dismiss_type='snoozed')
  2. 새 알람 생성 (DB + Native)
  3. 새 알람이 울리면 새 이력 생성 (alarm_id는 새 ID, snooze_count는 그대로 or 증가)
- [ ] **스누즈한 알람을 다시 끄면 'dismissed' 기록**
- [ ] **스누즈한 알람이 타임아웃되면 'timeout' 기록**

### 4.4 이력 누락 방지
- [ ] **알람이 리스트에서 사라지는 모든 경로에서 이력 기록:**
  - CustomAlarmReceiver (울림)
  - AlarmActivity dismissAlarm/timeoutAlarm/snoozeAlarm
  - AlarmOverlayService dismissAlarm/timeoutAlarm/snoozeAlarm
  - AlarmActionReceiver (Notification 버튼)
  - Flutter alarm_provider deleteAlarm (사용자 수동 삭제)
  - Flutter schedule_provider resetSchedule (교대근무 초기화)
- [ ] **DB 삭제 전에 반드시 이력 기록**

### 4.5 이력 조회 및 표시
- [ ] **설정 탭 "알람 이력" 버튼 → all_alarms_history_view 이동**
- [ ] **날짜별로 그룹화 표시**
- [ ] **각 이력에 아이콘 표시:**
  - dismissed: ✅
  - timeout: ⏰
  - snoozed: 🔁
  - cancelled: ❌
  - deleted_by_user: 🗑️
- [ ] **"오늘", "어제", "N일 전" 표시**
- [ ] **10일 이상 지난 이력은 자동 삭제됨**

### 4.6 이력 삭제
- [ ] **10일 자동 삭제:** AlarmRefreshReceiver → deleteOldAlarmHistory
- [ ] **앱 시작 시 자동 삭제:** main.dart → DatabaseService.deleteOldAlarmHistory
- [ ] **테스트용 전체 이력 삭제:** settings_tab "모든 이력 삭제" 버튼

### 4.7 Edge Cases
- [ ] **알람이 울리는 동안 삭제되면:**
  - CustomAlarmReceiver에서 'ringing' 기록
  - Flutter 또는 Activity/Overlay에서 dismissed/timeout 기록
  - 이력 2개 생성 가능 (ringing만 있는 것 + 최종 상태)
  - 괜찮음 (디버깅에 도움)
- [ ] **네트워크 없어도 이력 정상 기록 (로컬 DB)**
- [ ] **재부팅 후에도 이력 보존**
- [ ] **알람 이력이 없는 알람은 없어야 함** (모든 경로에서 기록)

---

## 추가 테스트 항목

### 권한
- [ ] Notification 권한 없으면 요청
- [ ] Exact Alarm 권한 없으면 요청
- [ ] Overlay 권한 없으면 AlarmActivity로 폴백

### 배터리 최적화
- [ ] 배터리 최적화 예외 요청 안내
- [ ] 배터리 최적화 켜져있어도 알람 울림 (setExactAndAllowWhileIdle)

### 다양한 시나리오
- [ ] 비행기 모드에서도 알람 울림
- [ ] 무음 모드에서도 알람 소리 남
- [ ] 여러 알람이 동시에 울릴 때 순차 처리
- [ ] 앱 강제 종료 후에도 알람 울림
- [ ] 데이터 삭제 후 재설치 → 온보딩 화면

### 성능
- [ ] 10일치 알람 생성 시간 < 3초
- [ ] 달력 스와이프 부드러움
- [ ] 앱 시작 속도 < 2초
- [ ] 알람 울림 즉시 반응

---

## 발견된 버그 (수정 필요 시)

### LOW 우선순위
- [ ] database_service.dart:20-24 - Race Condition (동시 DB 초기화)
- [ ] alarm_provider.dart - MethodChannel 매번 생성 (이미 static const로 수정됨)
- [ ] alarm_history.dart:29-30 - DateTime.parse 예외 미처리
- [ ] AlarmGuardReceiver.kt:20 - shownNotifications synchronized 안 됨
- [ ] CustomAlarmReceiver.kt:124 - WakeLock 하드코딩 (10초 고정)
- [ ] calendar_tab.dart:420-427 - FutureBuilder 에러 처리 누락
- [ ] settings_tab.dart:58 - 정렬 시 Null 체크 누락
- [ ] next_alarm_tab.dart:224 - COUNT 대신 getAllAlarms (비효율)

### 이미 수정됨
- [x] CRITICAL: 유령 알람 (clearShownNotifications 추가로 해결)
- [x] CRITICAL: Notification 동기화 (모든 삭제 경로에 추가)
- [x] HIGH: 날짜 계산 버그 (date.year 두 번 사용)
- [x] HIGH: Cursor 리소스 누수
- [x] MEDIUM: 스누즈 미구현
- [x] MEDIUM: 시간 계산 불일치
- [x] MEDIUM: 재부팅 시 갱신 플래그 미리셋
