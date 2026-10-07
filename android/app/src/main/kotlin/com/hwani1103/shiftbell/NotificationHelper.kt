// android/app/src/main/kotlin/com/example/shiftbell/NotificationHelper.kt

package com.hwani1103.shiftbell

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Notification 관련 공통 유틸리티
 * - showUpdatedNotification: 스누즈 결과 Notification 표시
 * - scheduleNotificationDeletion: 30초 후 8889 자동 삭제
 */
object NotificationHelper {

    private const val CHANNEL_ID = "shiftbell_result_v3"
    private const val NOTIFICATION_ID_SNOOZE = 8889
    private const val DELETE_REQUEST_CODE = 9999
    private const val TAG = "NotificationHelper"

    /** ID stays stable; the tag isolates each round from OS notification snoozing. */
    const val RING_CONTROL_ID = 7777

    /** 1.0.22까지 홈 버튼 제어 알림이 쓰던 채널(교차 검토 X-10) - 새로 만들지 않고, 이미 있을 때 폴백으로만 사용 */
    private const val LEGACY_CONTROL_CHANNEL_ID = "alarm_control"

    enum class RingNoticeReason { SELECTION, LOCALE, USER_LEAVE, COVER_ENTER, COVER_EXIT }
    private data class Publication(val ring: RingingAlarmTracker.ActiveRing, val label: String,
        val duration: Int, val initialWhen: Long, var cover: Boolean = false,
        var presented: Boolean = false, var pendingLocale: Context? = null,
        var coverOwner: java.lang.ref.WeakReference<Any>? = null,
        var fullScreenToken: PendingIntent? = null, var quietAfterCover: Boolean = false)
    private var publication: Publication? = null
    internal fun resetMemoryForTest() { publication = null }

    internal fun ringTag(ring: RingingAlarmTracker.ActiveRing) = "shiftbell:ring:${ring.alarmId}:${ring.round}"

    /** Includes snoozed (not active) notices and survives process death. Stale callers cannot cancel a newer round. */
    fun cancelRingControls(context: Context, alarmId: Int? = null, round: Long? = null) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        fun matches(id: Int, value: Long) = (alarmId == null || alarmId == id) && (round == null || round == value)
        val prefs = context.createDeviceProtectedStorageContext().getSharedPreferences("ring_notice", 0)
        if (matches(prefs.getInt("alarm", -1), prefs.getLong("round", -1))) {
            prefs.getString("tag", null)?.let { manager.cancel(it, RING_CONTROL_ID) }
            prefs.edit().clear().commit()
        }
        manager.activeNotifications.filter { it.id == RING_CONTROL_ID }.forEach {
            if (matches(it.notification.extras.getInt("shiftbell.copy.alarm", -1),
                    it.notification.extras.getLong("shiftbell.copy.round", -1))) manager.cancel(it.tag, it.id)
        }
        // The pre-tag version could leave a snoozed untagged notice after upgrade.
        if (alarmId == null) manager.cancel(RING_CONTROL_ID)
        publication?.takeIf { matches(it.ring.alarmId, it.ring.round) }?.let {
            it.fullScreenToken?.cancel()
            publication = null
        }
    }

    private fun live(context: Context, ring: RingingAlarmTracker.ActiveRing) =
        RingingAlarmTracker.isLiveRing(context) && RingingAlarmTracker.isCurrent(context, ring.alarmId, ring.round)

    /** The only FSI entry point. A failed post is not retried as another FSI. */
    fun postInitialRing(context: Context, alarmId: Int, round: Long, label: String, durationMinutes: Int) {
        val ring = RingingAlarmTracker.ActiveRing(alarmId, round)
        if (!live(context, ring) || publication?.ring == ring) return
        cancelRingControls(context)
        publication = Publication(ring, label, durationMinutes, System.currentTimeMillis())
        showRingControlNotification(context, alarmId, round, label, durationMinutes, false, true)
    }

    fun ensureRingControls(context: Context, alarmId: Int, round: Long, label: String,
                           durationMinutes: Int, reason: RingNoticeReason, surfaceOwner: Any? = null) {
        val ring = RingingAlarmTracker.ActiveRing(alarmId, round)
        if (!live(context, ring)) return
        val state = publication?.takeIf { it.ring == ring }
            ?: Publication(ring, label, durationMinutes, System.currentTimeMillis()).also { publication = it }
        if (reason == RingNoticeReason.COVER_EXIT && surfaceOwner != null && state.coverOwner?.get() !== surfaceOwner) return
        if (reason == RingNoticeReason.COVER_EXIT && state.cover) state.quietAfterCover = true
        if (reason == RingNoticeReason.COVER_ENTER) state.coverOwner = surfaceOwner?.let { java.lang.ref.WeakReference(it) }
        state.presented = true
        state.fullScreenToken?.cancel()
        state.cover = when (reason) {
            RingNoticeReason.COVER_ENTER -> true
            RingNoticeReason.COVER_EXIT -> false
            else -> state.cover
        }
        showRingControlNotification(context, alarmId, round, label, durationMinutes, state.cover, false)
    }

    fun markRingPresented(context: Context, ring: RingingAlarmTracker.ActiveRing) {
        val state = publication?.takeIf { it.ring == ring && live(context, ring) } ?: return
        state.presented = true
        state.fullScreenToken?.cancel()
        val pending = state.pendingLocale
        state.pendingLocale = null
        if (pending != null) NotificationLocale.refresh(pending)
    }

    fun refreshExistingRing(context: Context, ring: RingingAlarmTracker.ActiveRing, reason: RingNoticeReason) {
        val state = publication?.takeIf { it.ring == ring && live(context, ring) } ?: return
        if (reason == RingNoticeReason.LOCALE && !mayRefreshRingLocale(context, ring.alarmId, ring.round)) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val old = manager.activeNotifications.firstOrNull { it.id == RING_CONTROL_ID && it.tag == ringTag(ring) }?.notification ?: return
        if (old.extras.getInt("shiftbell.copy.alarm", -1) != ring.alarmId ||
            old.extras.getLong("shiftbell.copy.round", -1) != ring.round) return
        showRingControlNotification(context, ring.alarmId, ring.round, state.label, state.duration,
            state.cover, false, old)
    }

    internal fun mayRefreshRingLocale(context: Context, alarmId: Int, round: Long): Boolean {
        val ring = RingingAlarmTracker.ActiveRing(alarmId, round)
        val state = publication?.takeIf { it.ring == ring && live(context, ring) } ?: return false
        if (!state.presented) {
            state.pendingLocale = context.applicationContext.createConfigurationContext(context.resources.configuration)
            return false
        }
        return true
    }

    /**
     * 스누즈 결과 Notification 표시 (8889)
     * 1. 8889 표시
     * 2. 30초 후 자동 삭제 예약
     * 3. AlarmGuardReceiver.triggerCheck() 호출 (8888은 그 안에서 전담 갱신됨)
     */
    fun showUpdatedNotification(
        context: Context,
        newTimeStr: String,
        label: String
    ) {
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // ⭐ 8888은 AlarmGuardReceiver가 전담 (아래 triggerCheck가 재계산함) - 여기서 직접 cancel하지 않음

        // 채널 생성 ("알람" 키워드 제거 - 삼성 시스템 스누즈 방지)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.channel_alarm_result),
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = context.getString(R.string.channel_result_description)
                enableVibration(false)
                setSound(null, null)
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }

        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("openTab", 0)
        }
        val openAppPendingIntent = PendingIntent.getActivity(
            context,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 2단계: 8889 표시 (스누즈 결과)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .addExtras(NotificationLocale.metadata(context, "snooze", newTimeStr))
            .setContentTitle(context.getString(R.string.notif_snoozed_title, newTimeStr))
            .setContentText(label)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)  // ⭐ 알람시계 아이콘
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setAutoCancel(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setGroup("shiftbell_notifications")  // 삼성 시스템 스누즈 방지
            .setGroupSummary(false)
            .setLocalOnly(true)  // 삼성 시스템 스누즈 방지
            .setStyle(NotificationCompat.BigTextStyle().bigText(label))  // 삼성 시스템 스누즈 방지
            .setContentIntent(openAppPendingIntent)
            .build()

        notificationManager.notify(NOTIFICATION_ID_SNOOZE, notification)
        Log.d("NotificationHelper", "📢 8889 Notification 표시: $newTimeStr")

        // 3단계: 30초 후 8889 자동 삭제 예약
        scheduleNotificationDeletion(context)

        // 4단계: 다음 알람의 8888 Notification 표시
        AlarmGuardReceiver.triggerCheck(context)
        Log.d("NotificationHelper", "✅ AlarmGuardReceiver.triggerCheck() → 다음 알람 8888 표시")
    }

    /**
     * ⭐ 2026-09-14 (출시전 감사 #4) - 울리는 즉시 게시하고 울림이 끝날 때까지 유지하는 제어 알림(7777).
     *
     * 예전엔 끌 수단이 화면(잠금화면 AlarmActivity/해제 상태 오버레이)뿐이었음:
     *  - 잠금 상태에서 백그라운드 Activity 실행이 예외 없이 조용히 막히면 폴백도 안 타서 소리만 남음
     *  - 오버레이 권한이 없을 때의 폴백 알림엔 끄기/스누즈 버튼이 없었음
     *  - 7777은 잠금화면에서 홈을 눌렀을 때만 게시됐음
     * 이제 CustomAlarmReceiver가 소리와 동시에 이 알림을 올리고(전체화면 인텐트 + 탭하면 알람 화면 +
     * 끄기/5분 후 버튼), 화면·오버레이는 그다음에 시도함. 알림은 끄기·스누즈·인계·타임아웃에서만 지움
     * (AlarmActionHelper.closeRingUi 등). 커버 전용 화면에서는 중복 배너를 제거하기 위해
     * 같은 ID의 LOW/STATUS 제어 알림으로 교체하며 끄기/스누즈 액션은 유지한다.
     * 커버 화면에서 벗어나면 기존 채널로 복원하되 전체화면을 다시 강제로 열지는 않는다.
     * 버튼은 전부 (ID, 회차)를 담아 #3 회차 관문(AlarmActionHelper.claimRingEnd)을 통과함.
     * 알림 권한까지 꺼져 있으면 보이지 않음 → 그 경우의 끄기 수단은 화면·오버레이와 #3 자동 종료뿐(잔여 위험).
     * 삼성 "시스템 스누즈" 회피용 설정(CATEGORY_CALL·그룹·localOnly·BigTextStyle, 채널명에 "알람" 없음)은
     * 기존 폴백 알림 그대로 유지.
     */
    private fun showRingControlNotification(context: Context, alarmId: Int, round: Long, label: String, durationMinutes: Int,
                                    coverVisible: Boolean, launchFullScreen: Boolean, existing: android.app.Notification? = null) {
        if (!live(context, RingingAlarmTracker.ActiveRing(alarmId, round))) return
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // 게시 전 상태 점검 - 막혀 있어도 게시는 시도하고(권한이 나중에 켜질 수 있음) 로그로 원인을 남김
        try {
            if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
                Log.w(TAG, "⚠️ 알림 권한 꺼짐 - 제어 알림이 안 보임(끄기 수단은 화면·오버레이·자동 종료뿐)")
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
                !notificationManager.canUseFullScreenIntent()) {
                Log.w(TAG, "⚠️ 전체화면 알림 허용 안 됨 - 잠금 상태에서 알람 화면이 자동으로 안 뜰 수 있음")
            }
        } catch (e: Exception) {
            Log.w(TAG, "알림 상태 점검 실패", e)
        }

        var channelId = if (Build.VERSION.SDK_INT >= 26) existing?.channelId ?: CustomAlarmReceiver.CHANNEL_ID else CustomAlarmReceiver.CHANNEL_ID
        if (existing == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CustomAlarmReceiver.CHANNEL_ID,
                "Shiftbell",  // ⭐ "알람" 제거 (삼성 시스템 스누즈 방지)
                NotificationManager.IMPORTANCE_HIGH  // fullScreenIntent를 위해 HIGH 유지
            ).apply {
                description = context.getString(R.string.channel_ring_description)
                enableVibration(false)
                setSound(null, null)  // 알림 자체는 무음 - 소리는 AlarmPlayer
            }
            notificationManager.createNotificationChannel(channel)
            val current = notificationManager.getNotificationChannel(CustomAlarmReceiver.CHANNEL_ID)
            if (current != null && current.importance == NotificationManager.IMPORTANCE_NONE) {
                // ⭐ 2026-09-14 (교차 검토 X-10) - 1.0.22까지 홈 버튼 제어 알림은 별도 채널(alarm_control)이었음. 사용자가 새
                // 채널만 막아 두고 옛 제어 채널은 허용해 둔 기기라면, 업데이트 뒤에도 제어 알림이 사라지지 않게 옛 채널로 게시.
                // 옛 채널은 새로 만들지 않음(이미 있는 설치에서만 사용).
                val legacy = notificationManager.getNotificationChannel(LEGACY_CONTROL_CHANNEL_ID)
                if (legacy != null && legacy.importance != NotificationManager.IMPORTANCE_NONE) {
                    channelId = LEGACY_CONTROL_CHANNEL_ID
                    Log.w(TAG, "⚠️ 알람 알림 채널 차단됨 - 옛 제어 채널(alarm_control)로 제어 알림 게시")
                } else {
                    Log.w(TAG, "⚠️ 알람 알림 채널이 사용자 설정으로 차단됨 - 제어 알림이 안 보임")
                }
            }
        }

        val screenIntent = Intent(context, AlarmActivity::class.java).apply {
            // Extras do not participate in PendingIntent identity. Without a
            // round-specific URI, UPDATE_CURRENT retargets an old button token
            // to the next ring (including the same alarm after snoozing).
            data = android.net.Uri.parse("shiftbell://ring-control/$alarmId/$round/screen")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION
            putExtra("alarmId", alarmId)
            putExtra("label", label)
            putExtra("alarmDuration", durationMinutes)
            putExtra(AlarmActionReceiver.EXTRA_RING_ROUND, round)
        }
        val screenPendingIntent = PendingIntent.getActivity(
            context, alarmId, screenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val state = publication?.takeIf { it.ring == RingingAlarmTracker.ActiveRing(alarmId, round) } ?: return
        if (launchFullScreen && state.fullScreenToken == null) {
            state.fullScreenToken = PendingIntent.getActivity(context, alarmId, Intent(screenIntent).apply {
                data = android.net.Uri.parse("shiftbell://ring-control/$alarmId/$round/initial-fsi")
            }, PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE)
        }
        val noticeTag = ringTag(state.ring)
        val dismissPendingIntent = PendingIntent.getBroadcast(
            context, alarmId + 10000,
            Intent(context, AlarmActionReceiver::class.java).apply {
                action = AlarmActionReceiver.ACTION_DISMISS_FROM_NOTIFICATION
                data = android.net.Uri.parse("shiftbell://ring-control/$alarmId/$round/dismiss")
                putExtra(AlarmActionReceiver.EXTRA_ALARM_ID, alarmId)
                putExtra(AlarmActionReceiver.EXTRA_RING_ROUND, round)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        if (existing == null && coverVisible && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (!RingingAlarmTracker.isCurrent(context, alarmId, round)) return
            if (notificationManager.getNotificationChannel(channelId)?.importance == NotificationManager.IMPORTANCE_NONE) return
            // Keep dismiss/snooze in the notification shade, without a duplicate cover banner.
            val coverChannel = "shiftbell_cover_controls"
            notificationManager.createNotificationChannel(NotificationChannel(
                coverChannel, "Shiftbell", NotificationManager.IMPORTANCE_LOW
            ).apply { setSound(null, null); enableVibration(false) })
            if (notificationManager.activeNotifications.any {
                    it.id == RING_CONTROL_ID && it.notification.channelId != coverChannel
                }) notificationManager.cancel(noticeTag, RING_CONTROL_ID)
            channelId = coverChannel
        }

        val selected = RingingAlarmTracker.selectionForLiveRing(context, RingingAlarmTracker.ActiveRing(alarmId, round)) ?: return
        val old = notificationManager.activeNotifications.firstOrNull { it.id == RING_CONTROL_ID && it.tag == noticeTag }?.notification
        if (old != null && ((Build.VERSION.SDK_INT >= 26 && old.channelId != channelId) ||
                old.extras.getInt("shiftbell.copy.alarm", -1) != alarmId || old.extras.getLong("shiftbell.copy.round", -1) != round)) {
            notificationManager.cancel(noticeTag, RING_CONTROL_ID) // Only a cover channel transition.
        }
        val notification = NotificationCompat.Builder(context, channelId)
            .addExtras(NotificationLocale.metadata(context, "ring", alarmId = alarmId, round = round))
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(label)
            .setContentText(context.getString(R.string.notif_ringing_content))
            .setPriority(if (coverVisible) NotificationCompat.PRIORITY_LOW else NotificationCompat.PRIORITY_HIGH)
            .setCategory(if (coverVisible) NotificationCompat.CATEGORY_STATUS else NotificationCompat.CATEGORY_CALL)
            // Keep alarm classification stable. This ONE_SHOT capability is cancelled on
            // presentation and never recreated by an update; the independent body tap remains usable.
            .apply { state.fullScreenToken?.let { setFullScreenIntent(it, !coverVisible) } }
            .setContentIntent(screenPendingIntent)
            // 알림을 치우는 것도 "알람 확인"(끄기)으로 취급 - 기존 7777과 같은 규칙
            .setDeleteIntent(dismissPendingIntent)
            .setOngoing(true)
            .setAutoCancel(false)
            .setWhen(publication?.initialWhen ?: System.currentTimeMillis())
            .setSound(null).setVibrate(null).setDefaults(0)
            // setSilent(true) rewrites groupAlertBehavior in AndroidX and makes Samsung
            // regroup/collapse the first update. ONLY_ALERT_ONCE suppresses update alerts.
            // A cover channel replacement is a new OS post, so ONLY_ALERT_ONCE alone
            // cannot mute a user-customized channel. Keep this round quiet after unfolding.
            .setSilent(coverVisible || state.quietAfterCover)
            .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_ALL)
            .setOnlyAlertOnce(true)
            .setGroup("shiftbell_notifications")
            .setGroupSummary(false)
            .setLocalOnly(true)  // ⭐ 삼성 시스템 스누즈 방지
            .apply { RingControlNotification.decorate(context, this, selected, label, coverVisible,
                publication?.initialWhen ?: System.currentTimeMillis(), dismissPendingIntent) }
            .build()

        try {
            context.createDeviceProtectedStorageContext().getSharedPreferences("ring_notice", 0).edit()
                .putString("tag", noticeTag).putInt("alarm", alarmId).putLong("round", round).commit()
            notificationManager.notify(noticeTag, RING_CONTROL_ID, notification)
            Log.d(TAG, "✅ 제어 알림 게시: id=$alarmId 회차=$round")
        } catch (e: Exception) {
            // Android 13+ 알림 권한 미허용 등
            Log.e(TAG, "❌ 제어 알림 게시 실패: id=$alarmId", e)
        }
    }

    fun showSnoozeFailure(context: Context, code: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, context.getString(R.string.channel_alarm_result),
            NotificationManager.IMPORTANCE_LOW).apply { setSound(null, null); enableVibration(false) })
        val message = SnoozeFeedback.message(context, code)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .addExtras(NotificationLocale.metadata(context, "snoozeFailure", code))
            .setContentTitle(context.getString(R.string.snooze_failure_title)).setContentText(message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setCategory(NotificationCompat.CATEGORY_STATUS).setPriority(NotificationCompat.PRIORITY_LOW)
            .setSilent(true).setOnlyAlertOnce(true).setAutoCancel(true).setLocalOnly(true)
            .setGroup("shiftbell_notifications").setGroupSummary(false).build()
        manager.notify(NOTIFICATION_ID_SNOOZE, notification)
        scheduleNotificationDeletion(context)
    }

    /**
     * 30초 후 8889 Notification 자동 삭제 예약
     */
    private fun scheduleNotificationDeletion(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val deleteIntent = Intent(context, AlarmActionReceiver::class.java).apply {
            action = AlarmActionReceiver.ACTION_DELETE_SNOOZE_NOTIFICATION
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            DELETE_REQUEST_CODE,
            deleteIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val deleteTime = System.currentTimeMillis() + 30_000  // 30초 후

        try {
            alarmManager.setExact(AlarmManager.RTC, deleteTime, pendingIntent)
        } catch (_: SecurityException) {
            alarmManager.set(AlarmManager.RTC, deleteTime, pendingIntent)
        }

        Log.d("NotificationHelper", "⏰ 30초 후 8889 삭제 예약")
    }
}
