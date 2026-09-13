// android/app/src/main/kotlin/com/example/shiftbell/MainActivity.kt

package com.hwani1103.shiftbell

import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import androidx.core.app.NotificationCompat


class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.hwani1103.shiftbell/alarm"
    private var methodChannel: MethodChannel? = null

    companion object {
        // ⭐ 2026-09-12 - 일정 알림(ScheduleNotificationReceiver.kt)이 알림을
        // 탭했을 때 심는 Intent extra 키. ScheduleNotificationReceiver도 같은
        // 상수를 참조해서 여기 이름이 바뀌면 그쪽도 컴파일 에러로 바로 드러남.
        const val EXTRA_OPEN_SCHEDULE_DATE = "openDateSchedule_date"
        const val EXTRA_OPEN_SCHEDULE_START_MINUTES = "openDateSchedule_startMinutes"

        // ⭐ 2026-09-13(사용자 신고 - "일정 알림 누르면 그냥 달력탭으로 와버림")
        // 원인: 앱이 완전히 종료된 콜드 스타트에서는 InitialRouter가 항상
        // MainScreen(initialIndex: kCalendarTabIndex)("달력탭 고정")로 먼저
        // 뜨고, handleOpenDateScheduleIntent()의 invokeMethod("openDateSchedule")는
        // Dart의 MainScreen이 아직 initState에서 setMethodCallHandler를 등록하기
        // 전에 도착하면 그냥 유실됨(Flutter MethodChannel은 핸들러가 없는 채로
        // 온 메시지를 큐잉하지 않음) - 그 결과 요청 자체가 통째로 씹혀서 그냥
        // 기본값인 달력 탭에 머무름. "Native가 밀어넣기(push)"만 믿지 않고,
        // Dart가 스스로 시작 시점에 "혹시 대기 중인 요청 있어?"라고 다시
        // 물어보는(pull) consumePendingScheduleOpen 핸들러를 추가해 타이밍과
        // 무관하게 항상 전달되도록 함. 앱이 이미 떠 있는 채로(warm) 탭한
        // 경우엔 기존 즉시 invokeMethod 경로가 정상 처리하므로 그대로 둠 -
        // 이 값은 그게 놓쳤을 때만 쓰이는 안전망.
        private var pendingScheduleOpenDate: String? = null
        private var pendingScheduleOpenStartMinutes: Int = 0
    }

    // ⭐ 사용자 데이터 백업("A번 요구사항") - MediaStore에 항상 파일 하나만 유지
    // (writeBackupFile/readBackupFile/cleanupOldBackupFiles 참고). 2026-09-01 - 파일명에
    // 날짜를 넣어달라는 요청으로 "ShiftBell_Backup_YYMMDD.json" 형식으로 변경 -
    // 파일관리자로 직접 열어봤을 때 언제 만든 백업인지 한눈에 보이게 하려는
    // 목적이라, 매일 새 파일이 쌓이는 게 아니라 여전히 "파일 하나"만 유지하고
    // 쓸 때마다 그날 날짜로 다시 이름 붙임. 정확한 이름은 매번 날짜가 바뀌므로
    // 매칭/정리 로직은 전부 접두어(BACKUP_DISPLAY_NAME_PREFIX)로 함.
    //
    // ⭐ 2026-09-11(사용자 신고 - "자동백업이 실제로 안 되고 있다, 폴더에 예전
    // 파일 하나만 있다") 재점검 - dev/prod 두 flavor(build.gradle.kts, applicationId
    // "com.hwani1103.shiftbell" vs ".dev")가 완전히 다른 앱인데도 지금까지 이
    // 접두어가 고정 문자열이라 **둘 다 정확히 같은 파일명 규칙으로 같은 폴더**
    // (Download/ShiftBell/)에 쓰고 있었음. 바로 위 readBackupFile() 주석에 이미
    // 적혀있듯 이 앱은 (OEM 버그 우회 목적으로) MediaStore를 selection 없이
    // "전체 스캔"해서 이름만으로 매칭/삭제하는 경로를 쓰는데, 이 상태에서 두
    // 앱이 같은 이름 규칙을 쓰면 - 특히 owner_package_name이 NULL로 남는
    // 기종(이미 확인된 삼성 버그)에서는 - 한쪽이 자기 백업인 줄 알고 다른 쪽
    // 앱이 방금 쓴 파일을 정리 대상으로 오인하거나, 이름 충돌로 MediaStore가
    // 삽입을 예기치 않게 처리할 여지가 있었음(둘 다 개발자가 dev 빌드로 자주
    // 테스트하면서 prod(스토어) 앱도 같이 쓰는 이 기기 환경에서 실제로 부딪힐
    // 수 있는 조합). packageName을 접두어에 항상 포함시켜 두 앱이 물리적으로도
    // 절대 같은 파일명을 안 쓰게 함 - 이러면 위 OEM 버그가 어떻게 작동하든
    // 이름 충돌 가능성 자체가 원천 차단됨(부수 효과로 파일관리자에서 어느
    // 설치본의 백업인지도 파일명만으로 바로 구분됨).
    // ⭐ 2026-09-13(사용자 신고 - "백업 파일명에 왜 hwani가 붙어있냐, 실제
    // 배포판에도 이러면 안 된다") - 원인: 위에서 packageName 전체
    // ("com.hwani1103.shiftbell")를 그대로 파일명에 박아넣어서, 실제
    // 스토어(prod) 배포판에서도 사용자 눈에 개발자 개인 식별자가 그대로
    // 노출되고 있었음(dev/prod 충돌 방지라는 목적 자체는 맞지만, 그 목적엔
    // "서로 다르기만 하면" 충분해서 patternName 전체를 노출할 필요가 없었음).
    // prod는 접미사 없이 깔끔하게, dev만 짧은 "_dev" 구분자를 붙이는 것으로
    // 바꿔서 목적(충돌 방지)은 그대로 유지하면서 실제 사용자에게 보이는
    // prod 파일명에서 패키지명이 완전히 사라지게 함.
    private val BACKUP_DISPLAY_NAME_PREFIX by lazy {
        val flavorSuffix = if (packageName.endsWith(".dev")) "_dev" else ""
        "ShiftBell_Backup${flavorSuffix}_"
    }
    private val BACKUP_RELATIVE_PATH = "Download/ShiftBell/"

    private fun buildBackupDisplayName(): String {
        val fmt = java.text.SimpleDateFormat("yyMMdd", java.util.Locale.US)
        return "$BACKUP_DISPLAY_NAME_PREFIX${fmt.format(java.util.Date())}.json"
    }

    // ⭐ 2026-09-01 - "자동 탐지"(readBackupFile, selection 없이 전체 스캔)가
    // 실기기에서 계속 실패해서 원인을 파봤더니, MediaStore에 저장된 그 행의
    // `owner_package_name`이 NULL이었음(정상이면 이 앱 패키지명이 자동으로
    // 찍혀야 함 - adb shell content query로 직접 확인). 그 값이 없으면 권한 없는
    // 일반 앱의 쿼리는 "내가 만든 파일"로 인식을 못 해 결과에서 아예 빠짐 -
    // 삼성 DownloadStorageProvider 쪽 버그/차이로 보임, 우리 쿼리 코드로는 고칠
    // 수 없는 영역. 그래서 자동 탐지가 실패했을 때를 위해 시스템 파일 선택기
    // (SAF, ACTION_OPEN_DOCUMENT)로 사용자가 직접 백업 파일을 고르는 경로를
    // 추가함 - 이건 소유권 메타데이터에 의존하지 않고 사용자가 명시적으로
    // 고른 파일에 대한 접근 권한을 그 자리에서 새로 받기 때문에 이 버그와
    // 무관하게 항상 동작함.
    private val REQUEST_CODE_PICK_BACKUP_FILE = 9081
    private var pendingBackupPickResult: MethodChannel.Result? = null

    // ⭐ 갱신 요청 수신용 Receiver
    private val refreshReceiver = object : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("MainActivity", "📡 Flutter UI 갱신 요청")
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            methodChannel?.invokeMethod("refreshAlarms", null)
        }, 300)
    }
}
    override fun onCreate(savedInstanceState: Bundle?) {
        // ⭐ 윈도우 배경을 즉시 설정 (wallpaper 노출 방지)
        window.setBackgroundDrawableResource(android.R.color.transparent)

        super.onCreate(savedInstanceState)

        // ⭐ BroadcastReceiver 등록은 onResume으로 이동 예정
        val filter = IntentFilter("com.hwani1103.shiftbell.FLUTTER_REFRESH")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(refreshReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(refreshReceiver, filter)
        }
        Log.d("MainActivity", "✅ RefreshReceiver 등록 완료")

        // ⭐ Intent 처리는 나중에 (윈도우 표시 후)
        window.decorView.post {
            handleStopAlarmIntent(intent)
            handleOpenTabIntent(intent)
            handleOpenDateScheduleIntent(intent)
        }
    }

    // ⭐ "pickBackupFile"(위 주석 참고)의 결과 수신 - 시스템 파일 선택기가 고른
    // 파일을 읽어서 대기 중이던 MethodChannel.Result를 완료함.
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CODE_PICK_BACKUP_FILE) return

        val pending = pendingBackupPickResult
        pendingBackupPickResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending?.success(null) // 사용자가 취소함
            return
        }
        try {
            val content = contentResolver.openInputStream(uri)?.use { input ->
                input.readBytes().toString(Charsets.UTF_8)
            }
            pending?.success(content)
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ 수동 선택한 백업 파일 읽기 실패", e)
            pending?.success(null)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(refreshReceiver)
            Log.d("MainActivity", "✅ RefreshReceiver 해제")
        } catch (e: Exception) {
            Log.e("MainActivity", "RefreshReceiver 해제 실패", e)
        }
    }
    
    // ✅ 변경
override fun onResume() {
    super.onResume()
    // ⭐ CRITICAL FIX: triggerCheck()는 DB를 동기적으로(블로킹) 읽음. onResume()은
    // 메인 스레드에서 실행되는데, 여기서 바로 부르면 - 특히 설치 직후 첫 실행처럼
    // Dart(sqflite)가 같은 DB 파일을 동시에 처음 생성하고 있는 순간과 겹치면 -
    // SQLite 락 경합으로 메인 스레드가 몇 초간 멈출 수 있음. 메인 스레드가 막히면
    // Flutter 엔진의 첫 프레임 렌더링도 같이 막혀서, 스플래시(앱 로고) 화면에서
    // 멈춘 것처럼 보임. 재실행 시 재현이 안 되는 이유: 그땐 DB가 이미 다 만들어져
    // 있어서 경합 자체가 없음 - "설치 직후 딱 한 번만" 증상과 정확히 일치함.
    // 20분 전 알림/다음 wakeup 예약은 UI 렌더링과 무관하니 백그라운드 스레드로 옮김.
    Thread {
        AlarmGuardReceiver.triggerCheck(this)
        // ⭐ 실제 수면 기록/자동 추정("C번 요구사항") - 앱을 열 때마다 수면 감지
        // 예약이 최신 상태(스케줄/설정 변경 반영)인지 다시 확인. 알람 로직과 완전히
        // 독립된 read-only 판단 + 별도 알람 예약이라 위 triggerCheck()에 영향 없음.
        // 2026-09-01 - ensureScheduled(예약만)이 아니라 checkNow(즉시 판정 + 재예약)로
        // 바꿔서, 앱을 여는 순간 진행 중이던 자동 감지 후보를 바로 종료(기상 시각
        // 추정)하고 "OO시~OO시 수면한 것으로 추정됩니다" 카드를 곧바로 보여줄 수 있게 함
        // - 예전엔 다음 20분 샘플링 알람이 울릴 때까지 "OO시부터 수면 중"으로 남아있었음.
        SleepDetectionReceiver.checkNow(this)
    }.start()
    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
        methodChannel?.invokeMethod("refreshAlarms", null)
    }, 300)
}
    
    // ✅ 변경
override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    handleStopAlarmIntent(intent)
    handleOpenTabIntent(intent)
    handleOpenDateScheduleIntent(intent)
    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
        methodChannel?.invokeMethod("refreshAlarms", null)
    }, 300)
}
    
    // ⭐ 알림 탭 시 다음알람 탭으로 이동
    // ⭐ 2026-09-07 - 예전엔 "tabIndex >= 0"으로 걸러서 음수 값은 아예 무시했는데,
    // 수면 위젯(SleepWidgetProvider.kt)이 "컨디션 탭으로 열기" 요청을 음수
    // 센티널(kOpenConditionTabSentinel, Dart main.dart 참고 - 로케일에 따라
    // 실제 탭 인덱스가 달라져서 Kotlin이 고정 숫자로 못 보냄)로 보내야 해서
    // hasExtra로 바꿈 - "extra가 아예 없으면 무시, 있으면(음수 포함) 그대로
    // Dart에 전달"로 의미가 정확해짐. 기존 호출부(0/kCalendarTabIndex=2)는
    // 전부 0 이상이라 동작 그대로 유지됨.
    private fun handleOpenTabIntent(intent: Intent?) {
        if (intent?.hasExtra("openTab") != true) return
        val tabIndex = intent.getIntExtra("openTab", -1)
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, CHANNEL).invokeMethod("openTab", tabIndex)
        }
    }

    // ⭐ 2026-09-12 - 일정 알림(ScheduleNotificationReceiver.kt)을 탭했을 때 -
    // 그 알림의 contentIntent가 심어둔 extras를 그대로 Dart로 릴레이함.
    // 위 handleOpenTabIntent와 같은 패턴(hasExtra로 "이 intent가 그 용도로 온
    // 게 맞는지"부터 확인) - 이 앱을 켜는 다른 모든 경로(런처 아이콘, 다른
    // 알림 등)의 intent는 이 extra가 없으므로 아무 영향 없음.
    private fun handleOpenDateScheduleIntent(intent: Intent?) {
        if (intent?.hasExtra(EXTRA_OPEN_SCHEDULE_DATE) != true) return
        val date = intent.getStringExtra(EXTRA_OPEN_SCHEDULE_DATE) ?: return
        val startMinutes = intent.getIntExtra(EXTRA_OPEN_SCHEDULE_START_MINUTES, 0)
        // ⭐ 콜드 스타트에서 아래 즉시 invokeMethod가 유실되더라도(위 companion
        // object 주석 참고) Dart가 나중에 consumePendingScheduleOpen으로 다시
        // 가져갈 수 있도록 항상 먼저 저장해둠.
        pendingScheduleOpenDate = date
        pendingScheduleOpenStartMinutes = startMinutes
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, CHANNEL).invokeMethod(
                "openDateSchedule",
                mapOf("date" to date, "startMinutes" to startMinutes)
            )
        }
    }


    private fun handleStopAlarmIntent(intent: Intent?) {
        when (intent?.action) {
            "STOP_ALARM" -> {
                val notificationId = intent.getIntExtra("notificationId", 0)
                
                AlarmPlayer.getInstance(applicationContext).stopAlarm()
                
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(notificationId)
                
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, CHANNEL).invokeMethod("onAlarmStopped", notificationId)
                }
            }
            "SNOOZE_ALARM" -> {
                val notificationId = intent.getIntExtra("notificationId", 0)
                
                AlarmPlayer.getInstance(applicationContext).stopAlarm()
                
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(notificationId)
                
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, CHANNEL).invokeMethod("onAlarmSnoozed", notificationId)
                }
            }
        }
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleGuardWakeup" -> {
                    scheduleGuardWakeup()
                    result.success(null)
                }
                "getDeviceProtectedStoragePath" -> {
                    val path = getDeviceProtectedStoragePath()
                    result.success(path)
                }
                "scheduleNativeAlarm" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val timestamp = call.argument<Long>("timestamp") ?: 0L
                    val label = call.argument<String>("label") ?: "알람"
                    val soundType = call.argument<String>("soundType") ?: "loud"
                    
                    scheduleNativeAlarm(id, timestamp, label, soundType)
                    result.success(null)
                }
                "cancelNativeAlarm" -> {
                    val id = call.argument<Int>("id") ?: 0
                    cancelNativeAlarm(id)
                    result.success(null)
                }
                // ⭐ 2026-09-12 - 일정관리 탭 "일정에 맞춰서 알림받기" 실제 예약.
                // 기존 알람(scheduleNativeAlarm)과 완전히 별개 경로 - 잠금화면/벨소리
                // 없이 가벼운 일반 알림 1건만 표시함(ScheduleNotificationScheduler.kt).
                "scheduleDateNotification" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val triggerAtMillis = call.argument<Long>("triggerAtMillis") ?: 0L
                    val date = call.argument<String>("date") ?: ""
                    val startMinutes = call.argument<Int>("startMinutes") ?: 0
                    val content = call.argument<String>("content") ?: ""
                    // ⭐ 2026-09-13 - 알림 첫 줄 시간 표시("HH:mm" 또는 "HH:mm - HH:mm")용.
                    val durationMinutes = call.argument<Int>("durationMinutes") ?: 0
                    ScheduleNotificationScheduler.schedule(
                        applicationContext, id, triggerAtMillis, date, startMinutes, content, durationMinutes
                    )
                    result.success(null)
                }
                "cancelDateNotification" -> {
                    val id = call.argument<Int>("id") ?: 0
                    ScheduleNotificationScheduler.cancel(applicationContext, id)
                    result.success(null)
                }
                // ⭐ 2026-09-13 - "일정관리 화면 사용하지 않기"(탭 숨기기) 시점에
                // 호출 - 예약된 일정 알림 + 이미 표시된 알림을 전부 없애 그
                // 탭으로 돌아가는 진입 경로 자체를 닫는다(ScheduleNotificationScheduler.kt
                // cancelAllFromDb 주석 참고). DB는 안 건드리므로 되돌릴 수 있음.
                "cancelAllScheduleNotifications" -> {
                    ScheduleNotificationScheduler.cancelAllFromDb(applicationContext)
                    result.success(null)
                }
                // ⭐ 2026-09-13 - "일정관리 화면 사용하기"(탭 복원) 시점에 호출 -
                // 재부팅 재예약과 완전히 같은 함수를 재사용해 숨겨져 있던 동안
                // 취소됐던 알림들을 원래 상태로 그대로 복원함.
                "rescheduleAllScheduleNotifications" -> {
                    ScheduleNotificationScheduler.rescheduleAllFromDb(applicationContext)
                    result.success(null)
                }
                // ⭐ 2026-09-13 - openDateSchedule 콜드스타트 유실 대비 pull 경로
                // (위 companion object 주석 참고). MainScreen.initState()가
                // setMethodCallHandler 등록 직후 한 번 호출해서 "혹시 그 사이에
                // 놓친 요청 있어?"라고 확인함.
                "consumePendingScheduleOpen" -> {
                    val date = pendingScheduleOpenDate
                    if (date != null) {
                        result.success(mapOf("date" to date, "startMinutes" to pendingScheduleOpenStartMinutes))
                        pendingScheduleOpenDate = null
                    } else {
                        result.success(null)
                    }
                }
                // ⭐ 즉시 push(invokeMethod("openDateSchedule"))가 실제로 Dart에
                // 도달해서 처리됐으면 Dart가 이걸 불러서 companion의 대기값을
                // 지움 - 안 지우면 다음번 완전히 무관한 콜드 스타트 때
                // consumePendingScheduleOpen이 이 오래된 값을 잘못 다시 꺼내
                // 쓸 수 있음(스테일 데이터 방지).
                "clearPendingScheduleOpen" -> {
                    pendingScheduleOpenDate = null
                    result.success(null)
                }
                "stopAlarm" -> {
                    AlarmPlayer.getInstance(applicationContext).stopAlarm()
                    result.success(null)
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(null)
                }
                "checkOverlayPermission" -> {
                    val hasPermission = checkOverlayPermission()
                    result.success(hasPermission)
                }
                // ⭐ 정확한 알람 권한 (Android 12+). 이게 꺼지면 알람이 정확한 시각에
                // 예약이 안 될 수 있는데, 지금까지 앱이 이걸 아예 확인을 안 하고 있었음.
                "checkExactAlarmPermission" -> {
                    result.success(checkExactAlarmPermission())
                }
                "requestExactAlarmPermission" -> {
                    requestExactAlarmPermission()
                    result.success(null)
                }
                "triggerMidnightCheck" -> {
                    triggerMidnightCheck()
                    result.success(null)
                }
                // ⭐ 테스트용: Native last_alarm_refresh 리셋
                "resetNativeRefreshFlag" -> {
                    resetNativeRefreshFlag()
                    result.success(null)
                }
                // ⭐ 테스트용: Native 갱신 강제 실행
                "forceNativeRefresh" -> {
                    forceNativeRefresh()
                    result.success(null)
                }
                "triggerGuardCheck" -> {
                    triggerGuardCheck()
                    result.success(null)
                }
                // ⭐ 2026-09-11 - 수면 자동 감지 "거부 학습"(SleepDetectionReceiver.kt
                // 상단 REJECT_* 주석 참고) - Dart(sleep_record_provider.dart)가
                // AUTO_DETECTED 기록을 "기록하지 않기"/삭제할 때마다 호출.
                "recordSleepAutoRejection" -> {
                    val startEpochMillis = call.argument<Long>("startEpochMillis")
                    if (startEpochMillis != null) {
                        SleepDetectionReceiver.recordRejection(applicationContext, startEpochMillis)
                    }
                    result.success(null)
                }
                // ⭐ 신규 추가
"cancelNotification" -> {
    // ⭐ 8888은 AlarmGuardReceiver가 전담 (여기서 직접 cancel하지 않음 - 다른 알람의 8888을 잘못 지울 수 있음)
    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    notificationManager.cancel(8889)  // 스누즈/타임아웃 알림
    AlarmGuardReceiver.triggerCheck(this)
    Log.d("MainActivity", "📢 Notification 삭제 (ID: 8889) + 8888 재계산")
    result.success(null)
}
                // ⭐ 모든 Notification 삭제
                "cancelAllNotifications" -> {
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.cancelAll()
                    Log.d("MainActivity", "🗑️ 모든 Notification 삭제 완료")
                    result.success(null)
                }
                // ⭐ shownNotifications 전체 초기화 (유령 Notification 방지)
                "clearShownNotifications" -> {
                    AlarmGuardReceiver.clearAllShownNotifications()
                    Log.d("MainActivity", "🗑️ shownNotifications 전체 초기화 완료")
                    result.success(null)
                }
                // ⭐ AlarmGuardReceiver 취소
                "cancelAlarmGuard" -> {
                    val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    val intent = Intent(this, AlarmGuardReceiver::class.java)
                    val pendingIntent = PendingIntent.getBroadcast(
                        this,
                        999999, // AlarmGuardReceiver의 고유 ID
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    alarmManager.cancel(pendingIntent)
                    pendingIntent.cancel()
                    Log.d("MainActivity", "🗑️ AlarmGuardReceiver 취소 완료")
                    result.success(null)
                }
                // ⭐ Overlay 종료 (외부에서 알람 끄기)
                "dismissOverlay" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: -1
                    val intent = Intent(AlarmOverlayService.ACTION_DISMISS_OVERLAY).apply {
                        setPackage(packageName)  // Android 13+ RECEIVER_NOT_EXPORTED 대응
                        putExtra(AlarmOverlayService.EXTRA_ALARM_ID, alarmId)
                    }
                    sendBroadcast(intent)
                    Log.d("MainActivity", "📡 Overlay DISMISS 브로드캐스트 발송: ID=$alarmId")
                    result.success(null)
                }
                // ⭐ Overlay 스누즈 (외부에서 알람 5분 후)
                "snoozeOverlay" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: -1
                    val intent = Intent(AlarmOverlayService.ACTION_SNOOZE_OVERLAY).apply {
                        setPackage(packageName)  // Android 13+ RECEIVER_NOT_EXPORTED 대응
                        putExtra(AlarmOverlayService.EXTRA_ALARM_ID, alarmId)
                    }
                    sendBroadcast(intent)
                    Log.d("MainActivity", "📡 Overlay SNOOZE 브로드캐스트 발송: ID=$alarmId")
                    result.success(null)
                }
                // ⭐ 진동 테스트 (설정 화면에서 미리보기)
                "testVibration" -> {
                    val strength = call.argument<Int>("strength") ?: 1
                    testVibration(strength)
                    result.success(null)
                }
                // ⭐ 알람 음량 미리듣기 (STREAM_ALARM 사용)
                "playPreviewSound" -> {
                    val soundFile = call.argument<String>("soundFile") ?: "alarmbell1"
                    val volume = call.argument<Double>("volume")?.toFloat() ?: 0.7f
                    playPreviewSound(soundFile, volume)
                    result.success(null)
                }
                // ⭐ 미리듣기 중지
                "stopPreviewSound" -> {
                    stopPreviewSound()
                    result.success(null)
                }
                // ⭐ 미리듣기 볼륨 변경 (슬라이더 실시간 반영)
                "updatePreviewVolume" -> {
                    val volume = call.argument<Double>("volume")?.toFloat() ?: 0.7f
                    updatePreviewVolume(volume)
                    result.success(null)
                }
                // ⭐ 알람이 울리는 중인지 확인
                "isAlarmRinging" -> {
                    val isRinging = AlarmPlayer.getInstance(applicationContext).isAlarmRinging()
                    result.success(isRinging)
                }
                // ⭐ 홈 화면 캘린더 위젯 즉시 갱신 (스케줄 저장/변경 직후 Flutter가 호출)
                "refreshCalendarWidget" -> {
                    CalendarWidgetProvider.requestUpdate(applicationContext)
                    result.success(null)
                }
                // ⭐ 실제 수면 기록 위젯 즉시 갱신 - Flutter에서 자동 감지 결과를
                // 확인/수정/폐기하는 등 sleep_records를 직접 쓴 직후에 호출(refreshCalendarWidget과
                // 동일 패턴). 위젯이 홈 화면에 없으면 SleepWidgetProvider.requestUpdate()
                // 내부에서 조용히 아무 것도 안 함.
                "refreshSleepWidget" -> {
                    SleepWidgetProvider.requestUpdate(applicationContext)
                    result.success(null)
                }
                // ⭐ 사용자 데이터 백업("A번 요구사항") - 기기 로컬 저장소(MediaStore
                // Downloads/ShiftBell 폴더)에 백업 파일 하나를 쓰고/읽음. 클라우드도
                // 로그인도 전혀 안 씀 - 백업복구_설계.md 참고. Android 10(Q) 미만은
                // 스코프드 스토리지 이전이라 미지원(success=false로 응답).
                "writeBackupFile" -> {
                    val content = call.argument<String>("content")
                    if (content == null) {
                        result.success(false)
                    } else {
                        result.success(writeBackupFile(content))
                    }
                }
                "readBackupFile" -> {
                    result.success(readBackupFile())
                }
                // ⭐ 설정 탭 "백업 데이터 불러오기"(사용 중인 앱 위에 다른 백업을
                // 덮어씀) 전용 - restoreAll()로 거의 모든 테이블을 한 번에 갈아
                // 끼운 뒤에는, 이미 메모리에 떠 있는 모든 Riverpod provider/화면
                // state/네이티브 캐시를 하나하나 무효화하는 것보다 프로세스를
                // 통째로 다시 시작하는 게 훨씬 안전함(신규 설치 때 온보딩을 갓
                // 통과한 것과 동일한 "깨끗한 시작" 상태를 그대로 재현) - CLAUDE.md에
                // 정리된 "복원 직후 앱이 평소처럼 시작되면 알람 갱신 로직이 알아서
                // 채운다"는 전제를 실제로 만족시키려면 진짜 재시작이 필요함.
                // 표준 Flutter API로는 프로세스 재시작이 안 돼서 네이티브에서 처리:
                // 런처 인텐트로 새 태스크를 띄우고 현재 프로세스를 강제 종료함.
                "restartApp" -> {
                    result.success(true)
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        val restartIntent = packageManager.getLaunchIntentForPackage(packageName)
                        restartIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                        if (restartIntent != null) startActivity(restartIntent)
                        Runtime.getRuntime().exit(0)
                    }, 300)
                }
                // ⭐ 자동 탐지(readBackupFile) 실패 시 수동 대안 - 시스템 파일 선택기로
                // 사용자가 직접 백업 파일을 고름(위 pendingBackupPickResult 주석 참고).
                // 결과는 비동기라 여기서 바로 result.success를 안 부르고
                // onActivityResult에서 완료함.
                "pickBackupFile" -> {
                    pendingBackupPickResult = result
                    // ⭐ type을 "application/json"으로 좁혔더니 실기기에서 정작
                    // 만든 백업 파일 자체가 선택기 목록/최근 항목에 안 뜨는 문제가
                    // 있었음 - EXTRA_MIME_TYPES는 type이 "*/*"일 때만 유효한
                    // 힌트로 동작하고, type을 구체적으로 지정하면 그 값과
                    // 정확히 일치하는 파일만 보여주는데, 파일의 실제 등록된
                    // MIME 타입이 기기/생성 경로에 따라 "application/json"과
                    // 정확히 일치하지 않을 수 있음(예: 확장자만으로 다르게
                    // 추정되는 경우). type을 "*/*"로 완전히 열어서 어떤 파일이든
                    // 보이게 하고, 고른 파일이 실제 백업인지는 이후 JSON
                    // 디코드로 검증함(permission_intro_screen.dart의
                    // _pickBackupManually 참고) - 못 고를 위험보다 잘못 고를
                    // 위험(바로 에러 토스트로 걸러짐)이 훨씬 안전함.
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }
                    // ⭐ 선택기의 기본 화면은 "최근" 탭인데, 이것도 MediaStore 인덱스
                    // 기반이라 owner_package_name=NULL 버그의 영향을 그대로 받아
                    // 우리 백업 파일이 안 보임(위 readBackupFile 주석의 그 버그와
                    // 동일 원인). 유저가 직접 폴더를 찾아 들어가게 두지 않고,
                    // AOSP 표준 ExternalStorageProvider의 문서 URI 규칙
                    // ("primary:상대경로")으로 선택기가 Download/ShiftBell 폴더를
                    // 곧장 열고 시작하게 힌트를 줌 - 이 경로는 MediaStore 쿼리를
                    // 안 거치고 파일시스템을 직접 나열하는 뷰라 그 버그의 영향을
                    // 안 받음. 일부 기기/런처가 이 힌트를 무시할 수 있어 실패해도
                    // 조용히 기본 동작(선택기는 뜨되 최근 탭에서 시작)으로 진행함.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val initialUri = android.provider.DocumentsContract.buildDocumentUri(
                                "com.android.externalstorage.documents",
                                "primary:Download/ShiftBell"
                            )
                            intent.putExtra(android.provider.DocumentsContract.EXTRA_INITIAL_URI, initialUri)
                        } catch (e: Exception) {
                            Log.e("MainActivity", "⚠️ 선택기 시작 폴더 지정 실패(기본 동작으로 진행)", e)
                        }
                    }
                    try {
                        startActivityForResult(intent, REQUEST_CODE_PICK_BACKUP_FILE)
                    } catch (e: Exception) {
                        Log.e("MainActivity", "❌ 백업 파일 선택기 실행 실패", e)
                        pendingBackupPickResult = null
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    
    // ⭐ AlarmGuardReceiver 초기 예약
    private fun scheduleGuardWakeup() {
        val intent = Intent(this, AlarmGuardReceiver::class.java)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        
        val midnight = java.util.Calendar.getInstance().apply {
            add(java.util.Calendar.DAY_OF_MONTH, 1)
            set(java.util.Calendar.HOUR_OF_DAY, 0)
            set(java.util.Calendar.MINUTE, 0)
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
        }.timeInMillis
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                midnight,
                pendingIntent
            )
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                midnight,
                pendingIntent
            )
        }
    }
    
    private fun triggerMidnightCheck() {
        val intent = Intent(this, AlarmGuardReceiver::class.java)
        sendBroadcast(intent)
    }

    // ⭐ 테스트용: Native SharedPreferences의 last_alarm_refresh 리셋
    private fun resetNativeRefreshFlag() {
        val deviceContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            createDeviceProtectedStorageContext()
        } else {
            applicationContext
        }
        val prefs = deviceContext.getSharedPreferences("alarm_state", Context.MODE_PRIVATE)
        prefs.edit().putLong("last_alarm_refresh", 0L).apply()
        Log.d("MainActivity", "✅ Native last_alarm_refresh 리셋 완료")
    }

    // ⭐ 테스트용: Native 갱신 강제 실행 (리셋 후 트리거)
    private fun forceNativeRefresh() {
        resetNativeRefreshFlag()
        val intent = Intent("com.hwani1103.shiftbell.REFRESH_ALARMS").apply {
            setPackage(packageName)
        }
        sendBroadcast(intent)
        Log.d("MainActivity", "✅ Native 갱신 강제 실행 완료")
    }
    
    private fun triggerGuardCheck() {
        // ⭐ sendBroadcast 대신 직접 호출 (더 확실하게 동작)
        AlarmGuardReceiver.triggerCheck(this)
        Log.d("MainActivity", "✅ AlarmGuardReceiver 직접 트리거")
    }
    
    private fun getDeviceProtectedStoragePath(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val deviceProtectedContext = createDeviceProtectedStorageContext()
            deviceProtectedContext.getDatabasePath("shiftbell.db").absolutePath
        } else {
            getDatabasePath("shiftbell.db").absolutePath
        }
    }
    
    // ⭐ 사용자 데이터 백업("A번 요구사항") - 이 앱 소유의 MediaStore 파일 하나로
    // 관리. 파일명은 매번 그날 날짜로 다시 붙지만(buildBackupDisplayName), 새
    // 파일을 성공적으로 쓴 뒤에 기존 걸 지워서(2026-09-04 순서 변경 - 아래 M3
    // 주석 참고) "백업 = 파일 하나" 원칙은 그대로 지킴(백업복구_설계.md 8장).
    // 클라우드/로그인 전혀 안 씀 - 기기 로컬 저장소만.
    //
    // Android 10(Q, API 29) 미만은 스코프드 스토리지 이전이라 MediaStore.Downloads
    // 컬렉션 자체가 없음 - 이 기능은 그 버전 미만에서는 미지원으로 두고
    // false/null을 반환함(Dart 쪽이 그에 맞는 안내를 보여줌). 이 앱의 minSdk(24)
    // 대비 낮은 비중일 것으로 판단해 legacy(WRITE_EXTERNAL_STORAGE 권한 기반)
    // 경로는 만들지 않음 - 필요해지면 그때 추가.
    // ⭐ 2026-09-04 - M3 수정(전체_코드_점검_리포트_2026-09-04.md). 예전엔 "삭제
    // 먼저 → 쓰기" 순서라, 쓰기가 실패하면(저장공간 부족, insert()가 null 반환,
    // 쓰기 도중 예외 등) 옛 백업은 이미 지워지고 새 백업도 없는 "백업 전멸"
    // 상태가 됐음(자동 백업 경로라 사용자에게 경고도 안 뜸). "쓰기 먼저 → 성공한
    // 뒤에만 옛 것 삭제"로 순서를 바꿔서, 실패해도 최소한 기존 백업은 그대로
    // 남게 함. 삭제 자체는 이 기기(삼성 등)에서 유일하게 신뢰할 수 있다고 이미
    // 검증된 "기억해둔 URI 직접 삭제" 경로(옛 deleteBackupFile() 로직, 아래
    // cleanupOldBackupFiles로 분리함)를 그대로 재사용함 - 새 URI를 기억하기 전에
    // 옛 URI를 먼저 읽어만 둠.
    private fun writeBackupFile(content: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            Log.w("MainActivity", "⚠️ 백업 저장 스킵 - Android 10(Q) 미만")
            return false
        }
        val prefs = getSharedPreferences("backup_prefs", Context.MODE_PRIVATE)
        val previousUriStr = prefs.getString("last_backup_uri", null)
        // ⭐ 2026-09-11 - 자동 백업이 조용히 안 되는 문제 재점검용 로그. 이 함수는
        // MethodChannel을 타고 native까지 도달했다는 뜻이라, 이 로그 한 줄만
        // 봐도 "Dart 쪽에서 아예 호출을 안 한 것"과 "호출은 됐는데 여기서
        // 실패한 것"을 구분할 수 있음.
        Log.d("MainActivity", "💾 백업 저장 시도(content=${content.length}자, prevUri=$previousUriStr)")

        return try {
            val resolver = contentResolver
            val displayName = buildBackupDisplayName()
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, displayName)
                put(MediaStore.Downloads.MIME_TYPE, "application/json")
                put(MediaStore.Downloads.RELATIVE_PATH, BACKUP_RELATIVE_PATH)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            if (uri == null) {
                Log.w("MainActivity", "❌ 백업 저장 실패 - insert()가 null 반환(name=$displayName)")
                return false
            }
            val stream = resolver.openOutputStream(uri)
            if (stream == null) {
                Log.w("MainActivity", "❌ 백업 저장 실패 - openOutputStream()이 null 반환(uri=$uri)")
                return false
            }
            stream.use { out ->
                out.write(content.toByteArray(Charsets.UTF_8))
            }

            // ⭐ 새 백업이 실제로 저장에 성공한 뒤에만: 다음 write() 때 지울 URI를
            // 갱신하고, 옛 백업(방금 저장한 새 백업이 아니라 그 이전 것)을 지움.
            prefs.edit().putString("last_backup_uri", uri.toString()).apply()
            cleanupOldBackupFiles(resolver, previousUriStr, keepUri = uri)

            Log.d("MainActivity", "✅ 백업 파일 저장 완료: $uri")
            true
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ 백업 파일 저장 실패", e)
            false
        }
    }

    // ⭐ 2026-09-01 - "백업했는데 재설치해도 복구 안내가 전혀 안 뜬다" 버그 조사.
    // 처음엔 RELATIVE_PATH 정확 매칭 문제로 보고 DISPLAY_NAME LIKE로 바꿨는데,
    // 실기기 logcat으로 확인해보니 그것도 아니었음 - **재설치 여부와 무관하게,
    // 같은 프로세스 안에서 방금 쓴 파일조차 selection(LIKE 포함)을 건 쿼리로는
    // 못 찾았고, delete도 매번 0건**이었음(그 결과 실제로 파일이 11개까지
    // 쌓여있는 걸 확인함). 이 기기가 삼성(로그에 DownloadStorageProvider 등장)
    // 이라 OEM 스토리지 프로바이더가 Downloads 컬렉션에 대한 selection(WHERE절)
    // 처리를 AOSP와 다르게 하는 것으로 보임 - selection을 아예 안 쓰는 방식으로
    // 완전히 우회함: 전체 목록을 selection 없이 가져와서 파일명은 코틀린에서
    // 직접 비교하고, 삭제도 개별 row URI로(ContentUris.withAppendedId) 하나씩
    // 지움 - 둘 다 selection/LIKE 없이 동작하는 가장 기본적인 경로라 OEM 프로바이더
    // 차이를 탈 위험이 훨씬 적음. 이 앱이 만드는 백업 파일 개수는 항상 소수라
    // 전체 목록을 가져오는 성능 부담도 없음.
    private fun readBackupFile(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return try {
            val resolver = contentResolver
            val projection = arrayOf(MediaStore.Downloads._ID, MediaStore.Downloads.DISPLAY_NAME)
            var bestId = -1L
            var bestName = ""
            var totalCount = 0
            resolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI, projection, null, null, null
            )?.use { cursor ->
                val idIdx = cursor.getColumnIndexOrThrow(MediaStore.Downloads._ID)
                val nameIdx = cursor.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME)
                while (cursor.moveToNext()) {
                    totalCount++
                    val name = cursor.getString(nameIdx) ?: continue
                    if (name.startsWith(BACKUP_DISPLAY_NAME_PREFIX)) {
                        val id = cursor.getLong(idIdx)
                        if (id > bestId) { bestId = id; bestName = name } // _ID가 큰 쪽 = 가장 최근 삽입
                    }
                }
            }
            Log.d("MainActivity", "🔍 Downloads 전체 ${totalCount}건 중 백업 후보: ${if (bestId >= 0) bestName else "없음"}")
            if (bestId < 0) return null
            val uri = ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, bestId)
            Log.d("MainActivity", "✅ 백업 파일 발견: $uri")
            resolver.openInputStream(uri)?.use { input ->
                return input.readBytes().toString(Charsets.UTF_8)
            }
            null
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ 백업 파일 읽기 실패", e)
            null
        }
    }

    // ⭐ 2026-09-01 - "백업을 여러 번 눌렀더니 shiftbell_backup (1).json,
    // (2).json... 이 계속 쌓인다" 버그의 진짜 원인 - 아래 selection-없는
    // 전체 스캔 방식도 이 기기에선 무용지물이었음: readBackupFile()에서 이미
    // 확인했듯 이 기기는 우리 앱이 만든 행의 owner_package_name이 NULL로
    // 남아서, 권한 없는 일반 앱 쿼리로는 **자기가 방금 쓴 파일조차 쿼리
    // 결과에 안 잡힘**(전체 스캔이 매번 0건). 그래서 쿼리에 의존하지 않는
    // 방법으로 바꿈: write 성공 시 그 URI를 SharedPreferences에 기억해뒀다가
    // (writeBackupFile 참고), 다음 write 전에는 쿼리 없이 "기억해둔 그 URI"를
    // 바로 지움 - 이건 쿼리가 아니라 이미 손에 쥔 URI에 대한 직접 삭제라
    // owner_package_name 문제와 무관하게 항상 동작함. 이 방법은 "같은 설치
    // 안에서 백업을 여러 번 누르는" 가장 흔한 중복 원인을 확실히 잡음.
    // (남은 한계: 재설치로 SharedPreferences가 초기화되면 이전 설치가 남긴
    // 파일은 기억을 못 해서 못 지움 - 아래 selection-없는 스캔을 보조로 계속
    // 시도해두면 이 버그가 없는 다른 기기에서는 그것까지 정리됨)
    // ⭐ 2026-09-04 - M3 수정으로 writeBackupFile()에서 분리됨(이름도
    // deleteBackupFile → cleanupOldBackupFiles로 변경 - 이제 "쓰기 전 삭제"가
    // 아니라 "새 백업([keepUri])이 이미 안전하게 저장된 뒤" 호출되는 순수 정리
    // 작업이라, 여기서 뭔가 실패해도 다음 백업 때 다시 정리되므로 무해함(예전
    // deleteBackupFile()과 동일한 2단계 전략을 그대로 유지 - 1) 기억해둔 "직전"
    // URI 직접 삭제 2) 보조로 selection 없는 전체 스캔. 이 기종(삼성)의
    // owner_package_name NULL 버그 우회 방법은 그대로 - 아래 주석 참고).
    private fun cleanupOldBackupFiles(
        resolver: android.content.ContentResolver,
        previousUriStr: String?,
        keepUri: android.net.Uri
    ) {
        var deleted = 0

        // 1) 기억해둔 "직전" URI를 직접 지움 - 쿼리를 안 타서 owner_package_name
        // 버그의 영향을 안 받는, 사실상 유일하게 이 기기에서 실제로 동작하는 경로.
        if (previousUriStr != null && previousUriStr != keepUri.toString()) {
            try {
                deleted += resolver.delete(android.net.Uri.parse(previousUriStr), null, null)
            } catch (e: Exception) {
                Log.e("MainActivity", "⚠️ 옛 백업 파일 삭제 실패(무시 - 다음 백업 때 재시도됨)", e)
            }
        }

        // 2) selection 없는 전체 스캔 - 이 기기에선 매번 0건이지만, 이 버그가
        // 없는 다른 기기(또는 재설치로 기억이 끊긴 이전 설치)에서는 여기서 나머지
        // 잔여 파일까지 정리됨. 방금 쓴 새 백업([keepUri])은 반드시 제외.
        try {
            val keepId = try { ContentUris.parseId(keepUri) } catch (e: Exception) { -1L }
            val idsToDelete = mutableListOf<Long>()
            resolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.Downloads._ID, MediaStore.Downloads.DISPLAY_NAME),
                null, null, null
            )?.use { cursor ->
                val idIdx = cursor.getColumnIndexOrThrow(MediaStore.Downloads._ID)
                val nameIdx = cursor.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME)
                while (cursor.moveToNext()) {
                    val name = cursor.getString(nameIdx) ?: continue
                    val id = cursor.getLong(idIdx)
                    if (name.startsWith(BACKUP_DISPLAY_NAME_PREFIX) && id != keepId) {
                        idsToDelete.add(id)
                    }
                }
            }
            for (id in idsToDelete) {
                val uri = ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, id)
                deleted += resolver.delete(uri, null, null)
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "⚠️ 백업 파일 전체 스캔 삭제 실패(무시)", e)
        }

        Log.d("MainActivity", "🗑️ 기존 백업 파일 정리: 총 ${deleted}개 삭제")
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!android.provider.Settings.canDrawOverlays(this)) {
                val intent = Intent(
                    android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    android.net.Uri.parse("package:$packageName")
                )
                startActivity(intent)
            }
        }
    }
    
    private fun checkOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            android.provider.Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    // ⭐ 정확한 알람 권한 확인 (Android 12=API31 미만은 이 권한 개념 자체가 없어서 항상 true)
    private fun checkExactAlarmPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.canScheduleExactAlarms()
        } else {
            true
        }
    }

    // ⭐ 정확한 알람 권한은 런타임 팝업이 없고, 시스템 설정 화면으로 보내는 것만 가능함
    // (오버레이 권한이랑 똑같은 방식)
    private fun requestExactAlarmPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val intent = Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                    data = android.net.Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } catch (e: Exception) {
                Log.e("MainActivity", "❌ 정확한 알람 설정 화면 열기 실패", e)
            }
        }
    }

    private fun scheduleNativeAlarm(id: Int, timestamp: Long, label: String, soundType: String) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        
        val intent = Intent(this, CustomAlarmReceiver::class.java).apply {
            data = android.net.Uri.parse("shiftbell://alarm/$id")
            putExtra(CustomAlarmReceiver.EXTRA_ID, id)
            putExtra(CustomAlarmReceiver.EXTRA_LABEL, label)
            putExtra(CustomAlarmReceiver.EXTRA_SOUND_TYPE, soundType)
        }
        
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                timestamp,
                pendingIntent
            )
        } else {
            alarmManager.setExact(
                AlarmManager.RTC_WAKEUP,
                timestamp,
                pendingIntent
            )
        }

        // ⭐ 알람 등록 후 AlarmGuardReceiver 직접 트리거 (20분 이내면 Notification 표시)
        AlarmGuardReceiver.triggerCheck(this)
        Log.d("MainActivity", "✅ 알람 등록 완료: ID=$id, AlarmGuardReceiver 직접 트리거")
    }

    private fun cancelNativeAlarm(id: Int) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, CustomAlarmReceiver::class.java).apply {
            data = android.net.Uri.parse("shiftbell://alarm/$id")
        }
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarmManager.cancel(pendingIntent)

        // ⭐ shownNotifications에서 제거 (같은 ID 재사용 시 notification 표시 위해)
        AlarmGuardReceiver.removeShownNotification(id)
        Log.d("MainActivity", "✅ 알람 취소 및 shownNotifications 제거: ID=$id")
    }
    
    // ⭐ 진동 테스트 (약 1초간)
    private fun testVibration(strength: Int) {
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator

        // 진동 패턴 (1초간)
        val pattern = when(strength) {
            1 -> longArrayOf(0, 500, 200, 300)   // 약하게: 짧은 진동
            3 -> longArrayOf(0, 800, 200)        // 강하게: 긴 진동
            else -> longArrayOf(0, 500)
        }

        // 진동 세기
        val amplitude = when(strength) {
            1 -> 100   // 약하게
            3 -> 255   // 강하게 (최대)
            else -> 150
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val amplitudes = pattern.map { if (it == 0L) 0 else amplitude }.toIntArray()
            vibrator.vibrate(
                android.os.VibrationEffect.createWaveform(pattern, amplitudes, -1)  // -1 = 반복 안함
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(pattern, -1)
        }

        Log.d("MainActivity", "🔔 진동 테스트: 세기=$strength")
    }

    // ⭐ 미리듣기용 MediaPlayer
    private var previewMediaPlayer: android.media.MediaPlayer? = null
    private var previewLoudnessEnhancer: android.media.audiofx.LoudnessEnhancer? = null
    private var originalAlarmVolume: Int = -1  // ⭐ 원래 시스템 알람 볼륨 저장

    // ⭐ 알람 음량 미리듣기 (STREAM_ALARM 사용 - 실제 알람과 동일)
    private fun playPreviewSound(soundFile: String, volume: Float) {
        stopPreviewSound()  // 기존 재생 중지

        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager

            // ⭐ 원래 시스템 알람 볼륨 저장 (처음 한 번만)
            if (originalAlarmVolume == -1) {
                originalAlarmVolume = audioManager.getStreamVolume(android.media.AudioManager.STREAM_ALARM)
                Log.d("MainActivity", "📊 원래 시스템 알람 볼륨 저장: $originalAlarmVolume")
            }

            // ⭐ 시스템 알람 볼륨을 50%로 임시 변경 (미리듣기용)
            val maxVolume = audioManager.getStreamMaxVolume(android.media.AudioManager.STREAM_ALARM)
            val halfVolume = maxVolume / 2
            audioManager.setStreamVolume(android.media.AudioManager.STREAM_ALARM, halfVolume, 0)

            // ⭐ 사운드 URI 결정 (default = 시스템 기본 알람음)
            val soundUri = if (soundFile == "default") {
                android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_ALARM)
            } else {
                // res/raw 리소스 ID 가져오기
                val resourceId = resources.getIdentifier(soundFile, "raw", packageName)
                if (resourceId == 0) {
                    Log.e("MainActivity", "리소스 못 찾음: res/raw/$soundFile.mp3")
                    return
                }
                android.net.Uri.parse("android.resource://$packageName/$resourceId")
            }

            previewMediaPlayer = android.media.MediaPlayer().apply {
                setDataSource(this@MainActivity, soundUri)

                // 핵심: STREAM_ALARM 사용 (실제 알람과 동일)
                setAudioAttributes(
                    android.media.AudioAttributes.Builder()
                        .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                        .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )

                // ⭐ 실제 알람과 동일한 calibration 적용 (AlarmPlayer.kt와 동일한 커브)
                val calibrated = VolumeCalibration.linearGain(volume)
                setVolume(calibrated, calibrated)

                isLooping = false  // 미리듣기는 반복 안 함
                prepare()
                start()

                applyPreviewLoudnessBoost(audioSessionId, volume)
            }

            Log.d("MainActivity", "🔊 미리듣기 재생: $soundFile, 음량 ${(volume * 100).toInt()}%")

        } catch (e: Exception) {
            Log.e("MainActivity", "❌ 미리듣기 재생 실패", e)
        }
    }

    // ⭐ 미리듣기용 LoudnessEnhancer 적용 (실제 알람과 동일 체감 음량)
    private fun applyPreviewLoudnessBoost(audioSessionId: Int, sliderVolume: Float) {
        try {
            previewLoudnessEnhancer?.release()
            previewLoudnessEnhancer = android.media.audiofx.LoudnessEnhancer(audioSessionId).apply {
                setTargetGain(VolumeCalibration.boostMillibels(sliderVolume))
                enabled = true
            }
        } catch (e: Exception) {
            Log.w("MainActivity", "⚠️ 미리듣기 LoudnessEnhancer 미지원/실패", e)
        }
    }

    // ⭐ 미리듣기 중지
    private fun stopPreviewSound() {
        previewMediaPlayer?.apply {
            if (isPlaying) {
                stop()
            }
            release()
        }
        previewMediaPlayer = null
        try {
            previewLoudnessEnhancer?.release()
        } catch (e: Exception) {
            Log.e("MainActivity", "미리듣기 LoudnessEnhancer 해제 실패", e)
        } finally {
            previewLoudnessEnhancer = null
        }

        // ⭐ 시스템 알람 볼륨 복원
        if (originalAlarmVolume != -1) {
            try {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                audioManager.setStreamVolume(android.media.AudioManager.STREAM_ALARM, originalAlarmVolume, 0)
                Log.d("MainActivity", "🔄 시스템 알람 볼륨 복원: $originalAlarmVolume")
                originalAlarmVolume = -1  // 초기화
            } catch (e: Exception) {
                Log.e("MainActivity", "❌ 볼륨 복원 실패", e)
            }
        }

        Log.d("MainActivity", "🔇 미리듣기 중지")
    }

    // ⭐ 미리듣기 볼륨 변경 (슬라이더 실시간 반영)
    private fun updatePreviewVolume(volume: Float) {
        val calibrated = VolumeCalibration.linearGain(volume)
        previewMediaPlayer?.setVolume(calibrated, calibrated)
        previewMediaPlayer?.audioSessionId?.let { applyPreviewLoudnessBoost(it, volume) }
        Log.d("MainActivity", "🔊 미리듣기 볼륨 변경: ${(volume * 100).toInt()}%")
    }
}