package com.hwani1103.shiftbell

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class AlarmRefreshReceiver : BroadcastReceiver() {

    // ⭐ 실제 갱신 로직은 AlarmRefreshEngine 하나로 통일 (diff 기반, 트랜잭션, 락 보호)
    // 이 리시버는 트리거 진입점 역할만 함
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("AlarmRefresh", "========== 갱신 트리거 수신 ==========")
        AlarmRefreshEngine.refresh(context)
        Log.d("AlarmRefresh", "========== 갱신 처리 완료 ==========")
    }
}
