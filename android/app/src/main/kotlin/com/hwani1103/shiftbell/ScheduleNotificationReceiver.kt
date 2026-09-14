// android/app/src/main/kotlin/com/hwani1103/shiftbell/ScheduleNotificationReceiver.kt
//
// ⭐ 2026-09-12 - 일정관리 탭 "일정에 맞춰서 알림받기"가 실제로 울리는 지점.
// ScheduleNotificationScheduler.kt가 예약한 AlarmManager 알람을 여기서 받아
// 가벼운 일반 알림 1건을 띄운다. 기존 "알람"(CustomAlarmReceiver → AlarmActivity/
// AlarmOverlayService, 잠금화면·벨소리·스누즈·타임아웃)과는 완전히 별개 -
// 전체근무표_개선안_및_일정알림_설계메모.md 2장의 "일정관리는 알람이 아니라
// 알림" 원칙을 그대로 구현함.
//
// 알림 레이아웃(2026-09-13 재수정 - 사용자 피드백 "첫줄엔 시간, 둘째줄엔 내용"):
//   setContentTitle에 시각(시작만 있으면 "HH:mm", 지속시간이 있으면
//   "HH:mm - HH:mm"), setContentText에 일정 내용을 넣음(Android 알림의
//   기본 title/text 두 줄 레이아웃을 그대로 사용). BigTextStyle로 펼쳤을 때도
//   내용 전체가 줄바꿈 유지된 채로 다 보임(접힌 상태는 한 줄 + 말줄임표).
//   2026-09-12엔 "고정 제목(앱 이름 중복) 줄 삭제"만 했었는데, 이번엔 그
//   자리에 실제 정보(시각)를 다시 채운 것 - 예전의 "중복 제목 제거" 결론과
//   모순되지 않음(그때 지운 건 매번 똑같은 고정 문구였지, title 자체를 아예
//   쓰면 안 된다는 뜻은 아니었음).
// 탭하면 MainActivity를 열어 EXTRA_OPEN_SCHEDULE_DATE/START_MINUTES를 심어주고,
// handleOpenDateScheduleIntent(MainActivity.kt)가 Dart로 openDateSchedule을
// 릴레이해서 일정관리 탭 + 그 시간대로 이동시킴.
//
// 소리/진동/무음 - 이 알림 전용 Notification 채널("일정 알림")의 시스템 기본값을
// 그대로 따름. 여기서 setSound()/setVibrate()/setSilent() 등으로 강제하지 않음 -
// 사용자가 시스템 설정(앱 정보 > 알림 > "일정 알림")에서 직접 켜고 끌 수 있음.
//
// ⭐ 2026-09-13(사용자 신고 - "화면 켜져있을 때/사용 중일 때 헤드업(배너)
// 알림이 안 뜬다, 상태표시줄에만 생긴다") - 원인: 채널 importance가
// IMPORTANCE_DEFAULT였음. Android는 IMPORTANCE_HIGH 이상이어야 화면 위에
// 잠깐 떴다 사라지는 헤드업 배너를 띄운다(DEFAULT는 상태표시줄 아이콘 +
// 알림함에만 조용히 쌓임, 소리는 나지만 배너는 없음 - 정확히 신고된 증상과
// 일치). 소리/진동을 "시스템 기본값을 따른다"는 원칙 자체는 그대로 유지하고
// (여기서 강제 지정 안 함), importance만 한 단계 올려서 배너가 뜨게 함 -
// 사용자가 시스템 설정에서 이 채널의 알림 스타일을 낮추면 여전히 배너 없이
// 조용히 받을 수 있음(강제 배너가 아니라 "배너가 뜰 수 있는 채널"로 바뀔 뿐).
package com.hwani1103.shiftbell

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import java.util.Locale

class ScheduleNotificationReceiver : BroadcastReceiver() {

    companion object {
        private const val CHANNEL_ID = "schedule_notify_v2"
        private const val CHANNEL_NAME = "일정 알림"

        const val EXTRA_ID = "schedule_id"
        const val EXTRA_DATE = "schedule_date"
        const val EXTRA_START_MINUTES = "schedule_start_minutes"
        const val EXTRA_CONTENT = "schedule_content"
        const val EXTRA_DURATION_MINUTES = "schedule_duration_minutes"

        // ⭐ "HH:mm" 포맷 - 분(0~1439 기준, 자정을 넘긴 종료시각도 안전하게 처리).
        private fun formatMinutesOfDay(minutes: Int): String {
            val m = ((minutes % 1440) + 1440) % 1440
            return String.format(Locale.US, "%02d:%02d", m / 60, m % 60)
        }

        /** 시작만 있으면 "HH:mm", 지속시간까지 있으면 "HH:mm - HH:mm". */
        fun formatTimeHeadline(startMinutes: Int, durationMinutes: Int): String {
            if (durationMinutes <= 0) return formatMinutesOfDay(startMinutes)
            return "${formatMinutesOfDay(startMinutes)} - ${formatMinutesOfDay(startMinutes + durationMinutes)}"
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_ID, -1)
        if (id < 0) {
            Log.w("ScheduleNotify", "⚠️ id 없는 일정 알림 무시")
            return
        }
        // ⭐ 2026-09-14 (출시전 감사 #5, G1) - 예전엔 Intent에 담긴 예약 당시 내용을 그대로 표시해서, 일정 내용·시각을 바꾸거나
        // 알림을 끄거나 탭을 숨긴 뒤에도 남아 있던 옛 예약이 옛 내용·옛 시각으로 울렸음. 이제 DB로 다시 판정하고 DB 내용으로 표시.
        val expectedAt = if (intent.hasExtra(ScheduleNotificationScheduler.EXTRA_EXPECTED_AT)) {
            intent.getLongExtra(ScheduleNotificationScheduler.EXTRA_EXPECTED_AT, 0L)
        } else {
            null
        }
        val display = ScheduleNotificationScheduler.resolveOnReceive(context, id, expectedAt) ?: return
        val date = display.date
        val startMinutes = display.startMinutes
        val content = display.content
        val durationMinutes = display.durationMinutes
        val timeHeadline = formatTimeHeadline(startMinutes, durationMinutes)

        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // ⭐ IMPORTANCE_HIGH(위 파일 상단 주석 참고 - 헤드업 배너 노출 위해
            // DEFAULT에서 상향) + 사운드/진동을 명시적으로 지정하지 않음 - 채널
            // 생성 시점의 기본값(소리 O, 진동은 기기 설정 따름)이 그대로 "시스템
            // 알림 설정"이 되고, 사용자가 이후 시스템 설정 화면에서 이 채널만
            // 따로 켜고 끌 수 있음(요청: "시스템 알림설정 그대로 따르는 알림").
            // 채널 ID를 v1→v2로 바꿈 - Android는 채널 생성 후 importance를
            // "재생성 호출"만으로 바꿔주지 않으므로(사용자가 이미 v1 채널을 보고
            // 시스템 설정을 건드렸을 수도 있어 기존 채널 자체를 마이그레이션하는
            // 것도 위험) 새 채널로 분리 - 기존 v1 채널은 시스템에 그대로 남지만
            // 더 이상 알림을 안 보내므로 사용자가 알림함에서 안 보게 됨.
            // NotificationHelper.kt의 CHANNEL_ID("shiftbell_result_v3")는
            // 스누즈 결과 전용이라 여기서 재사용하지 않음 - 완전히 새 채널.
            val channel = NotificationChannel(
                CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "일정관리 탭에서 켠 일정 알림 - 소리/진동/무음은 이 채널 설정을 따름"
            }
            notificationManager.createNotificationChannel(channel)
        }

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            // ⭐ id별로 다른 data Uri - 여러 일정 알림을 연달아 탭해도 각각의
            // extras가 서로 뒤섞이지 않게(PendingIntent 캐시 충돌 방지, 위
            // ScheduleNotificationScheduler.buildPendingIntent와 같은 이유).
            data = android.net.Uri.parse("shiftbell://schedule_notify_open/$id")
            putExtra(MainActivity.EXTRA_OPEN_SCHEDULE_DATE, date)
            putExtra(MainActivity.EXTRA_OPEN_SCHEDULE_START_MINUTES, startMinutes)
        }
        val notifyId = id + ScheduleNotificationScheduler.REQUEST_CODE_OFFSET
        val contentPendingIntent = PendingIntent.getActivity(
            context, notifyId, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(timeHeadline)
            .setContentText(content)
            .setStyle(NotificationCompat.BigTextStyle().bigText(content).setBigContentTitle(timeHeadline))
            .setSmallIcon(R.drawable.ic_stat_schedule_notify)
            // ⭐ PRIORITY_HIGH - Android O 미만(채널 importance가 없는) 기기에서도
            // 헤드업 배너가 뜨도록 함(O 이상은 위 채널 importance가 우선 적용됨).
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_EVENT)
            .setAutoCancel(true)
            .setContentIntent(contentPendingIntent)
            .build()

        notificationManager.notify(notifyId, notification)
        Log.d("ScheduleNotify", "📅 일정 알림 표시: id=$id date=$date time=$timeHeadline content=$content")
    }
}
