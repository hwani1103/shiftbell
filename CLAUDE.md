# Shiftbell 프로젝트 가이드

## 프로젝트 개요
교대 근무자를 위한 알람 앱. Flutter + Kotlin Native로 구현.

### 핵심 기술 스택
- **Frontend**: Flutter (Dart), Riverpod 상태 관리
- **Backend**: Kotlin Native (Android)
- **DB**: SQLite (sqflite) - Device Protected Storage 사용
- **통신**: MethodChannel (`com.example.shiftbell/alarm`)

---

## 현재 구현 완료 (약 80%)

### 핵심 기능
- 규칙적/불규칙 근무 스케줄 설정
- 근무별 알람 템플릿 시스템
- 10일치 알람 자동 생성 & 갱신
- 알람 울림 (잠금 화면: AlarmActivity, 해제 상태: Overlay)
- 20분 전 사전 알림 Notification
- 알람 스누즈 (5분 연장)
- 타임아웃 자동 종료

### Native 알람 동기화 시스템
앱을 열지 않아도 알람이 계속 갱신됨:

1. **AlarmGuardReceiver**: 자정 또는 알람 20분 전에 wakeup
2. **AlarmRefreshUtil.checkAndTriggerRefresh()**: 날짜 변경 체크
3. **AlarmRefreshReceiver**: 10일치 알람 재생성
4. **DirectBootReceiver**: 재부팅 시 긴급 알람 1개 등록

### 주요 파일 구조
```
lib/
├── models/
│   ├── alarm.dart
│   ├── alarm_history.dart
│   ├── alarm_template.dart
│   ├── alarm_type.dart
│   └── shift_schedule.dart
├── providers/
│   ├── alarm_provider.dart
│   └── schedule_provider.dart
├── screens/
│   ├── calendar_tab.dart
│   ├── next_alarm_tab.dart
│   ├── settings_tab.dart
│   └── onboarding_screen.dart
└── services/
    ├── alarm_refresh_helper.dart
    ├── alarm_refresh_service.dart
    ├── alarm_service.dart
    └── database_service.dart

android/app/src/main/kotlin/com/example/shiftbell/
├── MainActivity.kt
├── AlarmActivity.kt (잠금 화면 알람)
├── AlarmOverlayService.kt (해제 화면 알람)
├── AlarmPlayer.kt (소리 재생)
├── CustomAlarmReceiver.kt (알람 수신)
├── AlarmGuardReceiver.kt (사전 알림 & 감시)
├── AlarmRefreshReceiver.kt (10일치 재생성)
├── AlarmRefreshUtil.kt (갱신 트리거)
├── DirectBootReceiver.kt (재부팅 처리)
├── AlarmActionReceiver.kt (Notification 버튼 액션)
└── DatabaseHelper.kt (Native DB 접근)
```

---

## 구현 예정 기능 (약 20%)

### 1. 커스텀 알람 시스템 (우선순위: HIGH)
**예상 작업량**: 4-5시간

#### 구현 내용:
- DB 테이블 추가: `custom_alarm_templates`
- 설정 탭에 "커스텀 알람 관리" 섹션
- 템플릿 최대 6개, 각각 이름/이모지/알람타입/시간 설정
- 달력 팝업에서 날짜별로 커스텀 알람 할당 (하루 최대 3개)
- 알람 생성 시 `type='custom'`으로 구분

#### 왜 필요한가:
- 잔업, 출장, 비정기 일정 대응
- 경쟁 앱 대비 차별화 포인트

### 2. 메모 기능 (우선순위: MEDIUM)
**예상 작업량**: 2-3시간

#### 구현 내용:
- DB 테이블: `date_notes (date TEXT PRIMARY KEY, note TEXT)`
- 달력 팝업에서 메모 입력란 추가
- 메모 있는 날짜는 달력에 작은 아이콘 표시

### 3. 알람 타입 확장 (우선순위: LOW)
**예상 작업량**: 3-4시간

#### 구현 내용:
- 근무별 기본 알람 타입 지정
- 달력에서 날짜마다 타입 변경 가능
- 알람 타입별 지속 시간(duration) 사용자 설정

### 4. 설정 탭 편의 기능 (우선순위: LOW)
**예상 작업량**: 3-4시간

#### 구현 내용:
- 근무명 변경
- 고정 알람 시간 수정 UI
- 다시 알림(20분 전) 전역 on/off 토글
- 근무 패턴 전체 변경 (온보딩 화면 재사용)
- 규칙적 ↔ 불규칙 전환

---

## 버그 현황

### 수정 완료
| 버그 | 위치 | 상태 |
|------|------|------|
| 날짜 계산 버그 (`date.year` 두 번 사용) | settings_tab.dart | FIXED |
| Cursor 리소스 누수 | CustomAlarmReceiver.kt | FIXED |
| 스누즈 미구현 | AlarmOverlayService.kt | FIXED |
| 시간 계산 불일치 (ceil vs 다른 방식) | next_alarm_tab.dart | FIXED |
| 재부팅 시 갱신 플래그 미리셋 | DirectBootReceiver.kt | FIXED |

### 미수정 (LOW 우선순위)
| 버그 | 위치 | 설명 | 우선순위 |
|------|------|------|----------|
| Race Condition | database_service.dart:20-24 | 동시 DB 초기화 가능 | MEDIUM |
| MethodChannel 비효율 | alarm_provider.dart | 매번 새 채널 생성 | LOW |
| DateTime.parse 예외 미처리 | alarm_history.dart:29-30 | try-catch 없음 | LOW |
| 동시성 문제 | AlarmGuardReceiver.kt:20 | shownNotifications synchronized 안 됨 | LOW |
| WakeLock 하드코딩 | CustomAlarmReceiver.kt:124 | 10초 고정 | LOW |
| FutureBuilder 에러 처리 누락 | calendar_tab.dart:420-427 | hasError 체크 없음 | LOW |
| 정렬 시 Null 체크 누락 | settings_tab.dart:58 | date! 강제 언래핑 | LOW |
| 비효율적인 쿼리 | next_alarm_tab.dart:224 | COUNT 대신 getAllAlarms | LOW |

---

## 테스트 체크리스트

### 완료
- [x] Notification ↔ Overlay 동기화
- [x] next_alarm_tab 즉시 갱신
- [x] 타임아웃 테스트 (현재 1분 하드코딩)
- [x] 알람 이력 기록 & 표시

### 미완료
- [ ] 재부팅 후 알람 갱신 테스트
- [ ] 앱 미실행 상태에서 자정 갱신 테스트
- [ ] 커스텀 알람 시스템 (미구현)

---

## 중요 참고사항

### Device Protected Storage
```kotlin
// Native (Kotlin)
val deviceContext = context.createDeviceProtectedStorageContext()
val prefs = deviceContext.getSharedPreferences("alarm_state", Context.MODE_PRIVATE)
```

```dart
// Flutter
final deviceProtectedPath = await platform.invokeMethod('getDeviceProtectedStoragePath');
```

Flutter SharedPreferences와 Native alarm_state는 **다른 경로**에 저장됨!

### 테스트용 타임아웃 설정
현재 1분 하드코딩 (나중에 사용자 설정으로 변경 필요):
- `AlarmOverlayService.kt:154`: `alarmDuration = 1`
- `CustomAlarmReceiver.kt:142`: `val duration = 1`

### 알람 동기화 트리거 포인트
1. 알람 울릴 때 (`CustomAlarmReceiver.onReceive`)
2. 자정 (`AlarmGuardReceiver`)
3. 알람 끌 때/스누즈 때 (`AlarmOverlayService.dismissAlarm/snoozeAlarm`)
4. 앱 열 때 (`MainActivity.onCreate`)

---

## 개발 진행 방향 제안

### Option 1: 빠른 출시
현재 상태로 v1.0 출시 → 사용자 피드백 수집 → v1.1에서 커스텀 알람 추가

### Option 2: 완성도 높은 출시
커스텀 알람 시스템만 추가 (4-5시간) → v1.0 출시

### 권장 순서
1. 커스텀 알람 시스템 (차별화)
2. 메모 기능 (사용성)
3. 설정 탭 편의 기능 (장기 유저 만족도)
