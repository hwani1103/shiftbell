package com.hwani1103.shiftbell

import android.content.Context
import java.util.Calendar

/**
 * ⭐ 위젯에서 "빨간날 숫자를 빨간색으로" 표시하기 위한 공휴일 데이터.
 * calendar_tab.dart의 _fixedHolidays/_lunarHolidays를 그대로 복제함 - 이름(문구)까지는
 * 필요 없고(위젯엔 공휴일 이름 텍스트를 안 보여줌, 숫자 색만 바뀌면 됨) 날짜만 있으면 됨.
 *
 * ⚠️ 이건 Dart 쪽 목록의 "스냅샷 복제"라 두 파일이 서로 다른 언어라서 자동으로 동기화되지
 * 않음. 나중에 앱에서 공휴일 목록을 갱신/연장할 때(업데이트_가이드.md 참고) 이 파일도
 * 같이 업데이트해야 위젯의 빨간날 표시가 계속 맞음 - 지금은 2029년까지 커버되어 있어서
 * 당장은 여유 있음.
 */
object CalendarWidgetHolidays {
    // ⭐ 고정 공휴일 (매년 동일, MM-dd)
    private val FIXED_HOLIDAYS = setOf(
        "01-01", "03-01", "05-05", "06-06", "08-15", "10-03", "10-09", "12-25"
    )

    // ⭐ 음력/변동 공휴일 (연도별, yyyy-MM-dd)
    private val LUNAR_HOLIDAYS = setOf(
        // 2025년
        "2025-01-28", "2025-01-29", "2025-01-30", "2025-03-03", "2025-05-06",
        "2025-10-05", "2025-10-06", "2025-10-07", "2025-10-08",
        // 2026년
        "2026-02-16", "2026-02-17", "2026-02-18", "2026-03-02", "2026-05-24",
        "2026-05-25", "2026-06-03", "2026-08-17", "2026-09-24", "2026-09-25",
        "2026-09-26", "2026-10-05",
        // 2027년
        "2027-02-06", "2027-02-07", "2027-02-08", "2027-02-09", "2027-05-13",
        "2027-08-16", "2027-09-14", "2027-09-15", "2027-09-16", "2027-10-04",
        "2027-10-11", "2027-12-27",
        // 2028년
        "2028-01-26", "2028-01-27", "2028-01-28", "2028-05-02", "2028-10-02",
        "2028-10-03", "2028-10-04", "2028-10-05",
        // 2029년
        "2029-02-12", "2029-02-13", "2029-02-14", "2029-05-07", "2029-05-20",
        "2029-05-21", "2029-09-21", "2029-09-22", "2029-09-23", "2029-09-24"
    )

    /**
     * ⭐ 2026-09-23 (1.0.24 D) - Firebase 원격 변경분(holiday_sync_service.dart가 채널 setHolidayOverrides로 넘겨 줌).
     * add = 공휴일로 추가할 날짜, remove = 하드코딩 목록에서 뺄 날짜(yyyy-MM-dd). 없으면 하드코딩 목록만 사용.
     */
    data class Overrides(val add: Set<String> = emptySet(), val remove: Set<String> = emptySet()) {
        companion object { val EMPTY = Overrides() }
    }

    private const val PREFS = "holiday_overrides"

    fun saveOverrides(context: Context, add: Collection<String>, remove: Collection<String>) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putStringSet("add", add.toSet())
            .putStringSet("remove", remove.toSet())
            .apply()
    }

    fun overrides(context: Context): Overrides = try {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        Overrides(p.getStringSet("add", emptySet())!!.toSet(), p.getStringSet("remove", emptySet())!!.toSet())
    } catch (e: Exception) {
        Overrides.EMPTY
    }

    fun isHoliday(cal: Calendar, overrides: Overrides = Overrides.EMPTY): Boolean {
        val month = cal.get(Calendar.MONTH) + 1
        val day = cal.get(Calendar.DAY_OF_MONTH)
        val year = cal.get(Calendar.YEAR)
        val dateKey = "%04d-%02d-%02d".format(year, month, day)
        if (dateKey in overrides.add) return true
        if (dateKey in overrides.remove) return false

        val fixedKey = "%02d-%02d".format(month, day)
        if (FIXED_HOLIDAYS.contains(fixedKey)) return true
        return LUNAR_HOLIDAYS.contains(dateKey)
    }
}
