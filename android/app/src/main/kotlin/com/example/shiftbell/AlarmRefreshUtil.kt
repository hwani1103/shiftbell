// android/app/src/main/kotlin/com/example/shiftbell/AlarmRefreshUtil.kt

package com.example.shiftbell

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.util.*

object AlarmRefreshUtil {
    
    /**
     * 갱신 필요 여부 체크 & Native 갱신 실행
     * (하루 1회 중복 방지)
     */
    fun checkAndTriggerRefresh(context: Context) {
        try {
            val deviceContext = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                context.createDeviceProtectedStorageContext()
            } else {
                context
            }
            
            val prefs = deviceContext.getSharedPreferences("alarm_state", Context.MODE_PRIVATE)
            
            // ⭐ 날짜 체크 (하루 1회)
            val lastRefresh = prefs.getLong("last_alarm_refresh", 0L)  // ⭐ 0L
            val lastDate = Calendar.getInstance().apply { 
                timeInMillis = if (lastRefresh > 0L) lastRefresh else 0L  // ⭐ 0L
            }
            val today = Calendar.getInstance()
            
            val dateChanged = if (lastRefresh == 0L) {  // ⭐ 0L로 수정!
                true  // 첫 실행
            } else {
                lastDate.get(Calendar.DAY_OF_YEAR) != today.get(Calendar.DAY_OF_YEAR) ||
                lastDate.get(Calendar.YEAR) != today.get(Calendar.YEAR)
            }
            
            if (dateChanged) {
                Log.d("AlarmRefreshUtil", "🔄 날짜 변경 감지 - Native 갱신 실행")
                Log.d("AlarmRefreshUtil", "   마지막: ${lastDate.get(Calendar.YEAR)}-${lastDate.get(Calendar.MONTH)+1}-${lastDate.get(Calendar.DAY_OF_MONTH)}")
                Log.d("AlarmRefreshUtil", "   현재: ${today.get(Calendar.YEAR)}-${today.get(Calendar.MONTH)+1}-${today.get(Calendar.DAY_OF_MONTH)}")

                // ⭐ 플래그 먼저 저장 (Race Condition 방지)
                prefs.edit()
                    .putLong("last_alarm_refresh", System.currentTimeMillis())
                    .apply()

                // ⭐ 그 다음 AlarmRefreshReceiver 트리거
                val intent = Intent("com.example.shiftbell.REFRESH_ALARMS").apply {
                    setPackage(context.packageName)  // ⭐ 명시적 브로드캐스트 (안정성 향상)
                }
                context.sendBroadcast(intent)

                Log.d("AlarmRefreshUtil", "✅ Native 갱신 트리거 완료")
            } else {
                Log.d("AlarmRefreshUtil", "⏭️ 오늘 이미 갱신됨 (${today.get(Calendar.MONTH)+1}/${today.get(Calendar.DAY_OF_MONTH)}) - 스킵")
            }
        } catch (e: Exception) {
            Log.e("AlarmRefreshUtil", "❌ 갱신 체크 실패", e)
        }
    }
}