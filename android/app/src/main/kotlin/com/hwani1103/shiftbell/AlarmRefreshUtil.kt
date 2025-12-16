// android/app/src/main/kotlin/com/example/shiftbell/AlarmRefreshUtil.kt

package com.hwani1103.shiftbell

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.util.*

object AlarmRefreshUtil {
    
    /**
     * 갱신 필요 여부 체크 & Native 갱신 실행
     * - 재부팅 감지 시 갱신
     * - 날짜 변경 시 갱신 (하루 1회)
     */
    fun checkAndTriggerRefresh(context: Context) {
        try {
            val deviceContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                context.createDeviceProtectedStorageContext()
            } else {
                context
            }

            val prefs = deviceContext.getSharedPreferences("alarm_state", Context.MODE_PRIVATE)

            // ⭐ 1. 재부팅 감지
            val lastBootTime = prefs.getLong("last_boot_time", 0L)
            val lastCheckedBootTime = prefs.getLong("last_checked_boot_time", 0L)
            val rebootDetected = lastBootTime > lastCheckedBootTime

            // ⭐ 2. 날짜 체크 (하루 1회)
            val lastRefresh = prefs.getLong("last_alarm_refresh", 0L)
            val lastDate = Calendar.getInstance().apply {
                timeInMillis = if (lastRefresh > 0L) lastRefresh else 0L
            }
            val today = Calendar.getInstance()

            val dateChanged = if (lastRefresh == 0L) {
                true  // 첫 실행
            } else {
                lastDate.get(Calendar.DAY_OF_YEAR) != today.get(Calendar.DAY_OF_YEAR) ||
                lastDate.get(Calendar.YEAR) != today.get(Calendar.YEAR)
            }

            // ⭐ 재부팅 또는 날짜 변경 시 갱신
            if (rebootDetected || dateChanged) {
                if (rebootDetected) {
                    Log.d("AlarmRefreshUtil", "🔄 재부팅 감지 - Native 갱신 실행")
                    Log.d("AlarmRefreshUtil", "   lastBootTime: $lastBootTime, lastCheckedBootTime: $lastCheckedBootTime")
                }
                if (dateChanged) {
                    Log.d("AlarmRefreshUtil", "🔄 날짜 변경 감지 - Native 갱신 실행")
                    Log.d("AlarmRefreshUtil", "   마지막: ${lastDate.get(Calendar.YEAR)}-${lastDate.get(Calendar.MONTH)+1}-${lastDate.get(Calendar.DAY_OF_MONTH)}")
                    Log.d("AlarmRefreshUtil", "   현재: ${today.get(Calendar.YEAR)}-${today.get(Calendar.MONTH)+1}-${today.get(Calendar.DAY_OF_MONTH)}")
                }

                // AlarmRefreshReceiver 트리거
                val intent = Intent("com.hwani1103.shiftbell.REFRESH_ALARMS")
                context.sendBroadcast(intent)

                // 갱신 완료 시각 & 부팅 시각 저장
                prefs.edit()
                    .putLong("last_alarm_refresh", System.currentTimeMillis())
                    .putLong("last_checked_boot_time", lastBootTime)
                    .apply()

                Log.d("AlarmRefreshUtil", "✅ Native 갱신 트리거 완료")
            } else {
                Log.d("AlarmRefreshUtil", "⏭️ 갱신 스킵 (재부팅 없음, 오늘 이미 갱신됨)")
            }
        } catch (e: Exception) {
            Log.e("AlarmRefreshUtil", "❌ 갱신 체크 실패", e)
        }
    }
}