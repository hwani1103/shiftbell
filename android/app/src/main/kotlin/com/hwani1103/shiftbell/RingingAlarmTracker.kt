package com.hwani1103.shiftbell

import android.content.Context
import android.content.SharedPreferences
import android.os.Build

/**
 * ⭐ 2026-08-25 추가 - "지금 화면/소리로 응답을 기다리고 있는 알람이 있는가"를 추적함.
 *
 * 배경: 알람 A가 아직 안 꺼진 채로(끄기/스누즈/타임아웃 전) 알람 B의 시각이 되면 무슨
 * 일이 일어나는지 점검한 결과 - AlarmPlayer(싱글턴)는 새 알람이 재생을 시작할 때 이전
 * mediaPlayer/vibrator를 정지시키므로 "소리는 항상 최신 알람 것 하나만" 나는 건 이미
 * 보장돼 있었음. 문제는 그 뒤:
 *  - 잠금화면(AlarmActivity): 알람마다 매번 새 Activity 인스턴스로 교체됨(구 인스턴스는
 *    그냥 destroy) - A의 DB 행/이력이 전혀 정리되지 않고 영구히 "유령 alarms 행"으로
 *    남았음(타임아웃도 dismiss도 한 번도 안 걸림).
 *  - 해제화면(AlarmOverlayService): 같은 Service 인스턴스가 재사용되는데,
 *    showOverlayWindow()가 "이미 표시 중이면 스킵"하는 로직 때문에 새 알람(B)의
 *    시간/근무명으로 뷰가 갱신되지 않고 화면엔 계속 A의 정보가 남아있는 채로
 *    내부 alarmId 필드만 B로 바뀌는 화면-데이터 불일치가 있었음.
 *
 * 해결: CustomAlarmReceiver.onReceive()가 새 알람을 처리하기 직전에 "지금 응답
 * 대기 중인 알람이 있고, 그게 이번 알람과 다르면" 그 알람을 AlarmActionHelper.supersede()로
 * 깔끔하게 마무리(이력 기록 + DB 삭제 + notification 정리)한 뒤 이번 알람을 진행함.
 * AlarmOverlayService도 자기 알람 ID가 바뀌는 걸 감지하면 뷰를 강제로 다시 그림
 * (표시 데이터 불일치 방지) - 두 수정은 독립적이지만 서로를 보완함.
 *
 * Device Protected Storage를 씀(다른 alarm_state 값들과 동일한 이유 - 잠금 해제 전에도
 * CustomAlarmReceiver가 접근 가능해야 함).
 */
object RingingAlarmTracker {
    private const val PREFS_NAME = "alarm_state"
    private const val KEY_RINGING_ID = "currently_ringing_alarm_id"
    private const val NONE = -1

    private fun prefs(context: Context): SharedPreferences {
        val deviceContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else {
            context
        }
        return deviceContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    /** 지금 응답 대기 중인 알람 ID, 없으면 null. */
    fun getRingingAlarmId(context: Context): Int? {
        val id = prefs(context).getInt(KEY_RINGING_ID, NONE)
        return if (id == NONE) null else id
    }

    /** 새 알람이 화면/소리를 시작할 때 호출 - "지금부터 이 알람이 응답 대기 중"으로 표시. */
    fun setRingingAlarmId(context: Context, id: Int) {
        prefs(context).edit().putInt(KEY_RINGING_ID, id).apply()
    }

    /** 이 id가 지금 추적 중인 값과 일치할 때만 지움(다른 알람이 이미 그 자리를 차지했으면
     * 건드리지 않음 - 순서가 꼬여도 안전하게). */
    fun clearIfMatches(context: Context, id: Int) {
        val p = prefs(context)
        if (p.getInt(KEY_RINGING_ID, NONE) == id) {
            p.edit().remove(KEY_RINGING_ID).apply()
        }
    }
}
