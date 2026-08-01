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

                // ⭐ CRITICAL FIX: setPackage()가 빠진 순수 암묵적(implicit) 브로드캐스트였음.
                // Android 8.0(API 26)+ 부터는 매니페스트에 등록된(static) 리시버는 암묵적
                // 브로드캐스트를 원칙적으로 못 받음 - 같은 앱 안에서 보내도 예외 없음.
                // AlarmRefreshReceiver가 매니페스트 등록 리시버라, 이 브로드캐스트가
                // 실제로는 전혀 전달되지 않고 있었을 가능성이 높음 (MainActivity.kt의
                // forceNativeRefresh()엔 이미 setPackage가 있었는데 - 그건 테스트 전용
                // 함수였고, 실제 자동 갱신 경로인 여기엔 빠져있었음). 그 결과 자정/20분전/
                // 알람울림/앱재개 등 모든 자동 트리거가 브로드캐스트를 보내기만 하고
                // AlarmRefreshEngine이 실제로 실행되는 일이 없었을 것으로 보임 - "10일치
                // 알람이 처음엔 생기고 그 뒤로 갱신이 전혀 안 되는" 증상의 근본 원인.
                // AlarmGuardReceiver.triggerCheck()도 결국 이 함수를 거치므로, 이 한 곳만
                // 고치면 모든 트리거 경로(자정/20분전/알람울림/앱재개)가 다 같이 고쳐짐.
                val intent = Intent("com.hwani1103.shiftbell.REFRESH_ALARMS").apply {
                    setPackage(context.packageName)
                }
                context.sendBroadcast(intent)

                // ⭐ CRITICAL FIX: "last_alarm_refresh"는 여기서 미리 찍지 않음.
                // sendBroadcast()는 fire-and-forget이라 실제 갱신(AlarmRefreshEngine.doRefresh)은
                // 이 함수가 끝난 뒤 비동기로 처리됨. 예전엔 여기서 곧바로 "오늘 갱신 완료"를
                // 찍어버려서, 그 비동기 처리가 (락 경합/예외/스케줄 미설정 등 어떤 이유로든)
                // 실제로 실패해도 다음 트리거가 "오늘은 이미 했음"으로 오판해서 재시도를
                // 안 하는 문제가 있었음 - 락이 고장나있을 땐 뭘 해도 다 통과돼서 이게 드러날
                // 일이 없었지만, 락을 실제로 작동하게 고친 지금은 경합으로 스킵된 시도가
                // 그대로 "그날 하루 통째로 누락"될 수 있음. 이제 이 플래그는 오직
                // AlarmRefreshEngine.markRefreshed()가 "실제로 성공했을 때만" 찍음 - 그래야
                // 실패한 시도는 다음 트리거(20분 뒤, 알람 울림, 앱 실행 등) 때 자동으로 재시도됨.
                prefs.edit()
                    .putLong("last_checked_boot_time", lastBootTime)
                    .apply()

                Log.d("AlarmRefreshUtil", "✅ Native 갱신 트리거 완료 (완료 표시는 실제 갱신 성공 시에만)")
            } else {
                Log.d("AlarmRefreshUtil", "⏭️ 갱신 스킵 (재부팅 없음, 오늘 이미 갱신됨)")
            }
        } catch (e: Exception) {
            Log.e("AlarmRefreshUtil", "❌ 갱신 체크 실패", e)
        }
    }
}