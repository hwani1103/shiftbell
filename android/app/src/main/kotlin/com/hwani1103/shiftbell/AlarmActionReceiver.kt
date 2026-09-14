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
 *
 * ⭐ 2026-09-14 (출시전 감사 #3) - 울림 회차별 자동 종료(ACTION_RING_TIMEOUT)도 여기서 받음.
 * 두 액션 모두 Intent의 (알람 ID, 회차)가 지금 울리는 회차일 때만 동작함(AlarmActionHelper.claimRingEnd).
 */
class AlarmActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_DELETE_SNOOZE_NOTIFICATION = "DELETE_SNOOZE_NOTIFICATION"
        const val ACTION_DISMISS_FROM_NOTIFICATION = "DISMISS_FROM_NOTIFICATION"
        const val ACTION_SNOOZE_FROM_NOTIFICATION = "SNOOZE_FROM_NOTIFICATION"
        const val ACTION_RING_TIMEOUT = "com.hwani1103.shiftbell.RING_TIMEOUT"
        const val EXTRA_ALARM_ID = "alarmId"
        const val EXTRA_RING_ROUND = "ringRound"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getIntExtra(EXTRA_ALARM_ID, 0)
        val round = intent.getLongExtra(EXTRA_RING_ROUND, RingingAlarmTracker.NO_ROUND)

        when (intent.action) {
            // ⭐ 30초 후 8889 자동 삭제
            ACTION_DELETE_SNOOZE_NOTIFICATION -> {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(8889)
                Log.d("AlarmAction", "🗑️ 8889 Notification 자동 삭제 (30초 경과)")
            }
            // ⭐ 울리는 중 알람 제어 Notification(7777)에서 "알람 끄기"
            ACTION_DISMISS_FROM_NOTIFICATION -> {
                Log.d("AlarmAction", "🔔 Notification에서 알람 끄기: ID=$alarmId 회차=$round")
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                // ⭐ 2026-09-14 (#3) - 이미 끝난 회차의 알림이면 다른 울림(같은 알람의 스누즈 후 재울림 포함)을
                // 건드리지 않음. 7777도 지우지 않음 - 같은 ID로 새 울림의 제어 알림이 이미 떠 있을 수 있음
                // (지난 회차 알림 자체는 그 울림이 끝날 때 이미 지워졌거나 새 알림으로 교체됨)
                if (!AlarmActionHelper.claimRingEnd(context, alarmId, round)) {
                    return
                }

                AlarmPlayer.getInstance(context).stopAlarm()
                // ⭐ 2026-09-14 (#4) - 제어 알림은 화면·오버레이가 떠 있어도 게시돼 있으므로 둘 다 닫고
                // 7777/8889도 정리(8888은 AlarmGuardReceiver가 전담 - dismiss가 재트리거함)
                AlarmActionHelper.closeRingUi(context, alarmId)
                AlarmActionHelper.dismiss(context, alarmId, "swiped")
                Log.d("AlarmAction", "✅ 알림에서 끄기 완료")
            }
            // ⭐ 2026-09-14 (출시전 감사 #4) - 제어 알림 "5분 후"(예전 7777엔 끄기만 있었음)
            ACTION_SNOOZE_FROM_NOTIFICATION -> {
                Log.d("AlarmAction", "🔔 Notification에서 5분 후: ID=$alarmId 회차=$round")
                if (!AlarmActionHelper.claimRingEnd(context, alarmId, round)) {
                    return
                }
                AlarmPlayer.getInstance(context).stopAlarm()
                AlarmActionHelper.closeRingUi(context, alarmId)
                val result = AlarmActionHelper.snooze(context, alarmId)
                if (result != null) {
                    NotificationHelper.showUpdatedNotification(context, result.newTimeStr, result.shiftType)
                } else {
                    Log.e("AlarmAction", "❌ 알림에서 스누즈 실패(알람 정보 없음): ID=$alarmId")
                }
            }
            // ⭐ 2026-09-14 (#3) - 울린 순간 CustomAlarmReceiver가 예약한 이 회차의 자동 종료
            ACTION_RING_TIMEOUT -> {
                if (!AlarmActionHelper.claimRingEnd(context, alarmId, round)) {
                    Log.d("AlarmAction", "⏰ 종료 예약 도착 - 이미 끝난 회차라 무시: ID=$alarmId 회차=$round")
                    return
                }
                Log.d("AlarmAction", "⏰ 종료 예약 도착 - 자동 종료: ID=$alarmId 회차=$round")
                AlarmPlayer.getInstance(context).stopAlarm()
                // 행이 있을 때만 timeout 이력을 남김(dismiss 내부) - 화면 타이머는 회차가 폐기돼 다시 기록하지 않음
                AlarmActionHelper.timeout(context, alarmId)
                AlarmActionHelper.closeRingUi(context, alarmId)
            }
        }
    }
}
