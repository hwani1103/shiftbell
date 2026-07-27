// android/app/src/main/kotlin/com/example/shiftbell/AlarmActionReceiver.kt

package com.hwani1103.shiftbell

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * ⭐ 알람이 "울리는 중" 상태를 제어하는 Notification(7777)의 버튼 액션만 처리함.
 *
 * 예전엔 여기서 20분 전 알림(8888)의 끄기/5분후 버튼도 같이 처리했는데(CANCEL_ALARM,
 * EXTEND_ALARM), 아직 울리지도 않은 알람을 제어하는 경로가 여러 개(달력 팝업, 다음알람 탭,
 * 이 알림)로 나뉘어 있다 보니 버그가 잦았음. 그래서 20분 전 알림은 정보 표시 전용(탭하면
 * 앱만 열림)으로 단순화했고, 여기는 "알람이 실제로 울리는 중 + 홈 버튼으로 화면을 벗어난"
 * 상황에서 소리를 멈출 유일한 안전장치로만 남김. DB 작업은 AlarmActionHelper 하나로 통일.
 */
class AlarmActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_DELETE_SNOOZE_NOTIFICATION = "DELETE_SNOOZE_NOTIFICATION"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getIntExtra("alarmId", 0)

        when (intent.action) {
            // ⭐ 30초 후 8889 자동 삭제
            ACTION_DELETE_SNOOZE_NOTIFICATION -> {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(8889)
                Log.d("AlarmAction", "🗑️ 8889 Notification 자동 삭제 (30초 경과)")
            }
            // ⭐ 울리는 중 알람 제어 Notification(7777)에서 "알람 끄기"
            "DISMISS_FROM_NOTIFICATION" -> {
                Log.d("AlarmAction", "🔔 Notification에서 알람 끄기: ID=$alarmId")

                val finishIntent = Intent("FINISH_ALARM_ACTIVITY").apply {
                    setPackage(context.packageName)
                    putExtra("alarmId", alarmId)
                }
                context.sendBroadcast(finishIntent)

                AlarmPlayer.getInstance(context).stopAlarm()

                AlarmActionHelper.dismiss(context, alarmId, "swiped")

                // ⭐ 8888은 AlarmGuardReceiver가 전담 (AlarmActionHelper.dismiss가 이미 재트리거함)
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(7777)
                notificationManager.cancel(8889)
                Log.d("AlarmAction", "✅ Notification 삭제 완료")
            }
        }
    }
}
