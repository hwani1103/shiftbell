package com.hwani1103.shiftbell

import android.content.Context
import android.util.Log
import java.util.Calendar

/**
 * ⭐ 실제 수면 기록/자동 추정("C번 요구사항") 전용 - "지금이 수면 가능성이 높은
 * 시간대(Sleep Opportunity Window)인가"를 백그라운드(Flutter 미실행 상태)에서도
 * 계산할 수 있게 하는 read-only 헬퍼.
 *
 * ⚠️⚠️ 이 파일의 알고리즘은 `lib/services/condition/sleep_opportunity.dart`와
 * **반드시 동일하게 유지**해야 한다 - 알람 생성 로직(alarm_generation_service.dart
 * ↔ AlarmRefreshEngine.kt)의 Dart/Kotlin 이중구현과 동일한 이유다. 한쪽만 고치면
 * 앱을 열었을 때 보이는 "수면 가능 시간대"와 백그라운드가 실제로 감지를 도는
 * 시간대가 서로 달라지는 버그가 생긴다 (수면기록_자동추정_설계.md 3장 참고).
 *
 * 근무 스케줄 자체를 읽는 부분은 `CalendarWidgetScheduleResolver`(기존, 수정 없음)를
 * 그대로 호출해서 재사용한다 - 패턴 순환/assignedDates 우선순위 계산을 세 번째로
 * 복제하지 않기 위함.
 *
 * ⭐ 2026-09-01 후속3 재설계 - "자동인식은 메인 잠 트래킹만, 폭을 최대한 줄이자"는
 * 요청으로 창을 다시 좁힘(sleep_opportunity.dart 상단 주석에 규칙 전문 - 요약:
 * 야간 근무는 종료 1시간 전부터, 그 외/휴무는 21시 이후부터, 둘 다 최대 9시간
 * 캡). 근무 중 짧은 낮잠은 이 창에 절대 포함되지 않음 - 위젯 수동 기록 전용.
 */
object SleepScheduleResolver {
    private const val TAG = "SleepScheduleResolver"

    // ⭐ shift_schedule.dart의 kUnsetShiftSentinel과 동일 문자열 유지할 것.
    private const val UNSET_SENTINEL = "미설정"

    // ⭐ sleep_opportunity.dart의 동명 상수와 값 동일하게 유지할 것.
    private const val NIGHT_SHIFT_PRE_END_MINUTES = 60L
    private const val FLAT_SLEEP_START_HOUR = 21
    private const val WINDOW_MAX_HOURS = 9L

    data class ShiftTimeRange(val startMinutes: Int, val endMinutes: Int) {
        val crossesMidnight: Boolean get() = endMinutes <= startMinutes
    }

    data class ResolvedInstance(
        val isWorkDay: Boolean,
        val isNight: Boolean,
        val startMillis: Long?,
        val endMillis: Long?
    )

    data class OpportunityWindow(
        val startMillis: Long,
        val endMillis: Long
    )

    // ⭐ lib/utils/shift_name_util.dart의 isRestShiftName()과 동일 로직 유지할 것.
    fun isRestShiftName(name: String): Boolean {
        if (name.contains("휴")) return true
        val lower = name.lowercase()
        return lower.contains("off") || lower.contains("rest") || lower.contains("holiday")
    }

    // ⭐ shift_time_category.dart의 classifyByStartMinutes()와 동일 로직 유지할 것
    // (17:00~04:59 시작이면 야간).
    private fun isNightStartMinutes(startMinutes: Int): Boolean {
        val h = (startMinutes / 60) % 24
        return !(h in 5..16) // 05:00~16:59가 아니면(=day/evening 아니면) 야간
    }

    /** 지금(nowMillis) 기준 수면 추적 창. 없으면 null(계산 불가/스케줄 없음). */
    fun computeWindowForNow(context: Context, nowMillis: Long): OpportunityWindow? {
        val schedule = CalendarWidgetScheduleResolver.readSchedule(context) ?: return null
        val conditionTimes = readConditionShiftTimes(context)

        val nowCal = Calendar.getInstance().apply { timeInMillis = nowMillis }
        val today = dayOnly(nowCal)

        // 1) 야간 근무 기준 - 오늘부터 최대 2일 전까지의 후보를 전부 모은 뒤,
        //    "이미 시작된(활성) 창"을 최우선으로 쓰고, 없으면 그중 가장 먼저
        //    시작하는(가장 이른 windowStart) 아직 시작 전 창을 쓴다.
        //
        //    ⚠️ 2026-09-01 버그 수정(백업_수면_컨디션_기능_검토_2026-09-01.md
        //    B1) - 이전엔 offset을 0(오늘)→2(그제) 순으로 보다가 "now가
        //    windowEnd보다만 이르면" 무조건 첫 매치를 반환했음. 연속
        //    야간근무(오늘도 야간 예정)일 때 offset=0(오늘, 아직 시작도 안 한
        //    밤 근무)의 창은 windowEnd가 아주 먼 미래라 이 조건을 쉽게
        //    통과해버려서, 실제로 지금 진행 중인 offset=1(어제 근무의 활성
        //    회복 창)을 확인하지도 못한 채 엉뚱한(미래) 창을 반환했다 - 그
        //    결과 어제 근무 후 낮잠을 자야 할 실제 구간에서 자동 감지가
        //    통째로 멈추는 버그였음. sleep_opportunity.dart와 동일하게 고침
        //    (Dart/Kotlin 알고리즘 동일 유지 원칙).
        var activeWindow: OpportunityWindow? = null
        var earliestUpcoming: OpportunityWindow? = null
        for (offset in 0..2) {
            val d = (today.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, -offset) }
            val inst = instanceForDate(schedule, conditionTimes, d)
            if (inst.isWorkDay && inst.isNight && inst.endMillis != null) {
                val windowStart = inst.endMillis - NIGHT_SHIFT_PRE_END_MINUTES * 60_000L
                val windowEnd = cappedEnd(schedule, conditionTimes, afterCal = d, fromMillis = windowStart)
                if (nowMillis >= windowEnd) continue // 이미 끝난 창 - 후보 아님

                if (nowMillis >= windowStart) {
                    // 지금 이미 이 창 안(진행 중) - 정상 스케줄에서는 활성 창이
                    // 동시에 두 개일 수 없지만, 방어적으로 더 늦게 시작한(더
                    // 최신인) 쪽을 택함.
                    if (activeWindow == null || windowStart > activeWindow!!.startMillis) {
                        activeWindow = OpportunityWindow(windowStart, windowEnd)
                    }
                } else {
                    // 아직 시작 전 - 가장 이르게 시작하는 후보만 남겨둠(활성
                    // 창이 끝내 없을 때의 폴백용).
                    if (earliestUpcoming == null || windowStart < earliestUpcoming!!.startMillis) {
                        earliestUpcoming = OpportunityWindow(windowStart, windowEnd)
                    }
                }
            }
        }
        if (activeWindow != null) return activeWindow
        if (earliestUpcoming != null) return earliestUpcoming

        // 2) 그 외 - "일상적인 수면 시간대"(21시~) 플랫 규칙. sleep_opportunity.dart의
        //    anchorDay 계산과 동일(자정~06시면 어제 21시, 그 외면 오늘 21시).
        val anchorDay = if (nowCal.get(Calendar.HOUR_OF_DAY) < 6) {
            (today.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, -1) }
        } else {
            today
        }
        var flatStart = (anchorDay.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, FLAT_SLEEP_START_HOUR)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        // ⭐ 2026-09-06(sleep_opportunity.dart와 동일 - Dart/Kotlin 알고리즘 동일
        // 유지 원칙) - 21시를 넘겨 끝나는 주간/오후 근무(예: 12시간 주간
        // 10~22시)라면 아직 근무 중에 창이 열리는 걸 막기 위해 "21시와 실제
        // 종료시각 중 더 늦은 쪽"부터 연다.
        val anchorInst = instanceForDate(schedule, conditionTimes, anchorDay)
        if (anchorInst.isWorkDay && !anchorInst.isNight && anchorInst.endMillis != null &&
            anchorInst.endMillis > flatStart) {
            flatStart = anchorInst.endMillis
        }
        val flatEnd = cappedEnd(schedule, conditionTimes, afterCal = anchorDay, fromMillis = flatStart)
        if (nowMillis < flatEnd) {
            return OpportunityWindow(flatStart, flatEnd)
        }

        return null
    }

    /** [fromMillis]로부터 [WINDOW_MAX_HOURS]를 더한 시각과, [afterCal] 이후 가장 가까운
     * 다음 근무 시작 시각 중 더 이른 쪽. */
    private fun cappedEnd(
        schedule: CalendarWidgetScheduleResolver.ResolvedSchedule,
        conditionTimes: Map<String, ShiftTimeRange>,
        afterCal: Calendar,
        fromMillis: Long
    ): Long {
        val cap = fromMillis + WINDOW_MAX_HOURS * 3_600_000L
        val nextStart = findNextWorkStart(schedule, conditionTimes, afterCal)
        return if (nextStart != null && nextStart < cap) nextStart else cap
    }

    private fun dayOnly(cal: Calendar): Calendar = (cal.clone() as Calendar).apply {
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }

    // ⭐ shift_pattern_analyzer.dart의 instanceForDate()와 동일 알고리즘.
    private fun instanceForDate(
        schedule: CalendarWidgetScheduleResolver.ResolvedSchedule,
        conditionTimes: Map<String, ShiftTimeRange>,
        dateCal: Calendar
    ): ResolvedInstance {
        val name = CalendarWidgetScheduleResolver.shiftForDate(schedule, dateCal)
        val isOff = isRestShiftName(name)
        val isUnset = name == UNSET_SENTINEL
        val isWorkDay = !isOff && !isUnset
        if (!isWorkDay) return ResolvedInstance(false, false, null, null)

        val range = conditionTimes[name] ?: return ResolvedInstance(true, false, null, null)
        val dayStartMillis = dayOnly(dateCal).timeInMillis
        val startMillis = dayStartMillis + range.startMinutes * 60_000L
        val endMillis = if (range.crossesMidnight) {
            dayStartMillis + (range.endMinutes + 24 * 60) * 60_000L
        } else {
            dayStartMillis + range.endMinutes * 60_000L
        }
        return ResolvedInstance(true, isNightStartMinutes(range.startMinutes), startMillis, endMillis)
    }

    private fun findNextWorkStart(
        schedule: CalendarWidgetScheduleResolver.ResolvedSchedule,
        conditionTimes: Map<String, ShiftTimeRange>,
        afterDayCal: Calendar,
        lookaheadDays: Int = 14
    ): Long? {
        for (i in 1..lookaheadDays) {
            val d = (dayOnly(afterDayCal).clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, i) }
            val inst = instanceForDate(schedule, conditionTimes, d)
            if (inst.isWorkDay && inst.startMillis != null) return inst.startMillis
        }
        return null
    }

    private fun readConditionShiftTimes(context: Context): Map<String, ShiftTimeRange> {
        val db = DatabaseHelper.getInstance(context).getReadableDatabaseWithRetry() ?: return emptyMap()
        val result = mutableMapOf<String, ShiftTimeRange>()
        try {
            db.query("condition_shift_times", null, null, null, null, null, null).use { cursor ->
                while (cursor.moveToNext()) {
                    val name = cursor.getString(cursor.getColumnIndexOrThrow("shift_name"))
                    val start = cursor.getInt(cursor.getColumnIndexOrThrow("start_minutes"))
                    val end = cursor.getInt(cursor.getColumnIndexOrThrow("end_minutes"))
                    result[name] = ShiftTimeRange(start, end)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ condition_shift_times 읽기 실패", e)
        }
        return result
    }
}
