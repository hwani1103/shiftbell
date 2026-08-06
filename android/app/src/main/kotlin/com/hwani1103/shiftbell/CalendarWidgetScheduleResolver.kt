package com.hwani1103.shiftbell

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

/**
 * ⭐ 홈 화면 위젯 전용 - "이 날짜엔 어떤 근무가 배정되어 있고, 무슨 색인가"만 순수하게
 * 읽어서 계산하는 read-only 헬퍼.
 *
 * 알람 시스템(AlarmRefreshEngine.kt)이 10일치 알람을 만들 때 쓰는 "패턴 순환 + assignedDates
 * 예외 우선" 계산과 완전히 동일한 알고리즘을 그대로 가져다 씀 - 로직을 두 곳에서 서로
 * 다르게 재구현하면 나중에 한쪽만 고쳐져서 위젯과 알람이 서로 다른 근무를 보여주는
 * 버그가 생길 수 있어서, 계산 방식(assignedDates 우선 → 패턴 인덱스)과 날짜 diff 계산
 * (Julian Day Number 기반, DST 안전)을 그대로 복제함. DB는 읽기만 하고 절대 쓰지 않음 -
 * 알람 갱신 로직(AlarmRefreshEngine)과는 완전히 독립된 경로라 서로 간섭하지 않음.
 */
object CalendarWidgetScheduleResolver {
    private const val TAG = "CalendarWidgetResolver"
    private const val DATE_FORMAT = "yyyy-MM-dd'T'HH:mm:ss"

    data class ResolvedSchedule(
        val isRegular: Boolean,
        val pattern: List<String>,
        val todayIndex: Int,
        val startDateMillis: Long,
        val assignedDates: Map<String, String>,
        val shiftColors: Map<String, Int>
    )

    // ⭐ shift_schedule 테이블에서 위젯 렌더링에 필요한 값만 읽음 (없으면 null)
    fun readSchedule(context: Context): ResolvedSchedule? {
        val db: SQLiteDatabase = try {
            DatabaseHelper.getInstance(context).getReadableDatabaseWithRetry() ?: return null
        } catch (e: Exception) {
            Log.e(TAG, "❌ DB 열기 실패", e)
            return null
        }

        return try {
            db.query("shift_schedule", null, null, null, null, null, null, "1").use { cursor ->
                if (!cursor.moveToFirst()) return null

                val isRegular = cursor.getInt(cursor.getColumnIndexOrThrow("is_regular")) == 1
                val assignedDatesStr = cursor.getString(cursor.getColumnIndexOrThrow("assigned_dates"))
                val shiftColorsStr = cursor.getString(cursor.getColumnIndexOrThrow("shift_colors"))
                val assignedDates = parseStringMap(assignedDatesStr)
                val shiftColors = parseColorMap(shiftColorsStr)

                if (!isRegular) {
                    return ResolvedSchedule(false, emptyList(), 0, 0L, assignedDates, shiftColors)
                }

                val patternStr = cursor.getString(cursor.getColumnIndexOrThrow("pattern"))
                val todayIndex = cursor.getInt(cursor.getColumnIndexOrThrow("today_index"))
                val startDateStr = cursor.getString(cursor.getColumnIndexOrThrow("start_date"))

                if (patternStr.isNullOrEmpty() || startDateStr.isNullOrEmpty()) {
                    return ResolvedSchedule(false, emptyList(), 0, 0L, assignedDates, shiftColors)
                }

                val parsedStart = try {
                    SimpleDateFormat(DATE_FORMAT, Locale.getDefault()).parse(startDateStr)
                } catch (e: Exception) {
                    Log.e(TAG, "❌ startDate 파싱 실패: $startDateStr", e)
                    return null
                } ?: return null

                val startCal = Calendar.getInstance().apply {
                    time = parsedStart
                    set(Calendar.HOUR_OF_DAY, 0)
                    set(Calendar.MINUTE, 0)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }

                ResolvedSchedule(
                    isRegular = true,
                    pattern = patternStr.split(","),
                    todayIndex = todayIndex,
                    startDateMillis = startCal.timeInMillis,
                    assignedDates = assignedDates,
                    shiftColors = shiftColors
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ 스케줄 읽기 실패", e)
            null
        }
        // ⭐ db.close() 하지 않음 - DatabaseHelper.kt/AlarmActionHelper.kt의 기존 방침과 동일
        // (SQLiteOpenHelper가 관리하는 공유 커넥션이라 여기서 닫으면 다른 경로가 깨짐)
    }

    // ⭐ 특정 날짜에 배정된 근무명. assignedDates(달력에서 수동 지정한 예외)가 최우선,
    // 그다음 패턴 순환. 둘 다 없으면 "미설정".
    fun shiftForDate(schedule: ResolvedSchedule, cal: Calendar): String {
        val dayKey = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(cal.time)
        schedule.assignedDates[dayKey]?.let { return it }

        if (!schedule.isRegular || schedule.pattern.isEmpty()) return "미설정"

        val startCal = Calendar.getInstance().apply { timeInMillis = schedule.startDateMillis }
        val daysDiff = julianDayNumber(cal) - julianDayNumber(startCal)
        val idx = ((schedule.todayIndex + daysDiff) % schedule.pattern.size + schedule.pattern.size) % schedule.pattern.size
        return schedule.pattern[idx]
    }

    // ⭐ AlarmRefreshEngine.kt의 julianDayNumber()와 동일 (DST/시간대 무관하게 날짜 수 차이 계산)
    private fun julianDayNumber(cal: Calendar): Int {
        val year = cal.get(Calendar.YEAR)
        val month = cal.get(Calendar.MONTH) + 1
        val day = cal.get(Calendar.DAY_OF_MONTH)
        val a = (14 - month) / 12
        val y = year + 4800 - a
        val m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    private fun parseStringMap(json: String?): Map<String, String> {
        if (json.isNullOrEmpty()) return emptyMap()
        return try {
            val obj = JSONObject(json)
            val map = mutableMapOf<String, String>()
            obj.keys().forEach { key -> map[key] = obj.getString(key) }
            map
        } catch (e: Exception) {
            Log.e(TAG, "❌ JSON(String) 파싱 실패", e)
            emptyMap()
        }
    }

    private fun parseColorMap(json: String?): Map<String, Int> {
        if (json.isNullOrEmpty()) return emptyMap()
        return try {
            val obj = JSONObject(json)
            val map = mutableMapOf<String, Int>()
            // ⭐ Dart는 64비트 int라 Color(0xFFRRGGBB).value 같은 큰 ARGB 값이 JSON에
            // 양수 그대로("4289505468" 등, Int32 범위 초과) 찍힘. org.json은 이런 값을
            // 내부적으로 Long으로 보관하는데 getInt()에 맡기면 내부 fallback 동작에
            // 암묵적으로 기대는 셈이라, 명시적으로 getLong() 후 .toInt()로 하위 32비트만
            // 잘라내서 원래의 signed 32비트 ARGB 값을 안전하게 복원함.
            obj.keys().forEach { key -> map[key] = obj.getLong(key).toInt() }
            map
        } catch (e: Exception) {
            Log.e(TAG, "❌ JSON(Color) 파싱 실패", e)
            emptyMap()
        }
    }
}
