package com.hwani1103.shiftbell

import android.app.ActivityManager
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.usage.UsageStatsManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * ⭐ 2026-09-23 (1.0.24 C) - "문제 신고용 진단 파일" 만들기. 내보내는 순간의 상태 스냅샷 + DiagLog 기록을 텍스트 파일 하나로
 * Download/ShiftBell/ShiftBell_Diag[_dev]_yyMMdd_HHmmss.txt 에 저장(이 종류는 항상 최신 1개만 유지)하고, 공유 시트를 띄울 URI를 돌려줌.
 * 스냅샷 항목의 의미·판정 기준은 docs/진단로그_해석_매뉴얼.md 참고.
 */
object DiagReport {
    private const val TAG = "DiagReport"
    private const val RELATIVE_PATH = "Download/ShiftBell/"

    private fun prefix(context: Context) =
        if (context.packageName.endsWith(".dev")) "ShiftBell_Diag_dev_" else "ShiftBell_Diag_"

    private fun fmt(ms: Long): String =
        if (ms <= 0L) "-" else SimpleDateFormat("yyyy-MM-dd HH:mm:ss Z", Locale.US).format(Date(ms))

    /** 스냅샷 본문(테스트·미리보기용으로 분리). 실패한 항목은 "?"로 남기고 계속. */
    fun buildSnapshot(context: Context): String {
        val sb = StringBuilder()
        fun line(k: String, v: () -> Any?) {
            val value = try { v() } catch (e: Exception) { "? (${e.javaClass.simpleName})" }
            sb.append(k).append(": ").append(value).append('\n')
        }
        val pm = context.packageManager
        sb.append("=== ShiftBell 진단 파일 ===\n")
        line("created") { fmt(System.currentTimeMillis()) }
        line("app") {
            val info = pm.getPackageInfo(context.packageName, 0)
            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
            "${context.packageName} ${info.versionName} ($code)"
        }
        line("installer") {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) pm.getInstallSourceInfo(context.packageName).installingPackageName
            else @Suppress("DEPRECATION") pm.getInstallerPackageName(context.packageName)
        }
        line("device") { "${Build.MANUFACTURER} ${Build.MODEL} (${Build.BRAND})" }
        line("android") { "${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})" }

        sb.append("\n--- 권한·제한 ---\n")
        line("notifications") { NotificationManagerCompat.from(context).areNotificationsEnabled() }
        line("alarmChannelImportance") {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                    .getNotificationChannel(CustomAlarmReceiver.CHANNEL_ID)?.importance ?: "missing"
            } else "n/a"
        }
        line("exactAlarm") {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).canScheduleExactAlarms()
            } else "n/a(<31)"
        }
        line("overlay") { if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.canDrawOverlays(context) else "n/a" }
        line("fullScreenIntent") {
            if (Build.VERSION.SDK_INT >= 34) {
                (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).canUseFullScreenIntent()
            } else "n/a(<34)"
        }
        line("batteryOptimizationIgnored") {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                (context.getSystemService(Context.POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(context.packageName)
            } else "n/a"
        }
        line("backgroundRestricted") {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).isBackgroundRestricted
            } else "n/a"
        }
        line("standbyBucket") {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                when (val b = (context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager).appStandbyBucket) {
                    UsageStatsManager.STANDBY_BUCKET_ACTIVE -> "ACTIVE"
                    UsageStatsManager.STANDBY_BUCKET_WORKING_SET -> "WORKING_SET"
                    UsageStatsManager.STANDBY_BUCKET_FREQUENT -> "FREQUENT"
                    UsageStatsManager.STANDBY_BUCKET_RARE -> "RARE"
                    45 -> "RESTRICTED"
                    else -> "OTHER($b)"
                }
            } else "n/a"
        }
        line("powerSaveMode") { (context.getSystemService(Context.POWER_SERVICE) as PowerManager).isPowerSaveMode }

        sb.append("\n--- 최근 프로세스 종료 사유(최신순, Android 11+) ---\n")
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val reasons = am.getHistoricalProcessExitReasons(context.packageName, 0, 8)
                if (reasons.isEmpty()) sb.append("(없음)\n")
                for (r in reasons) {
                    sb.append("${fmt(r.timestamp)} reason=${exitReason(r.reason)} importance=${r.importance} desc=${r.description ?: "-"}\n")
                }
            } else sb.append("n/a(<30)\n")
        } catch (e: Exception) {
            sb.append("? (${e.javaClass.simpleName})\n")
        }

        sb.append("\n--- 알람 상태 ---\n")
        line("lastAlarmRefresh") {
            val dp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) context.createDeviceProtectedStorageContext() else context
            fmt(dp.getSharedPreferences("alarm_state", Context.MODE_PRIVATE).getLong("last_alarm_refresh", 0L))
        }
        line("pendingOsRetryIds") { AlarmWakeScheduler.failedIds(context).sorted() }
        line("restoreLocked") { RestoreGate.isLocked(context) }
        sb.append("다음 알람 10개 (id | 예정 시각 | type | 종류 | OS 등록 여부):\n")
        try {
            val db = DatabaseHelper.getInstance(context).getReadableDatabaseWithRetry() ?: throw IllegalStateException("DB 없음")
            val now = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).format(Date())
            db.query("alarms", arrayOf("id", "date", "type", "alarm_type_id"), "date > ?", arrayOf(now),
                null, null, "date ASC", "10").use { c ->
                if (c.count == 0) sb.append("(없음)\n")
                while (c.moveToNext()) {
                    val id = c.getInt(0)
                    sb.append("$id | ${c.getString(1)} | ${c.getString(2)} | ${c.getInt(3)} | os=${isRegistered(context, id)}\n")
                }
            }
        } catch (e: Exception) {
            sb.append("? DB 읽기 실패 (${e.javaClass.simpleName}: ${e.message})\n")
        }

        sb.append("\n--- 백업 ---\n")
        val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        line("lastBackupManual") { flutterPrefs.getString("flutter.backup_last_saved_at_manual", "-") }
        line("lastBackupAuto") {
            flutterPrefs.getString("flutter.backup_last_saved_at_auto", null)
                ?: flutterPrefs.getString("flutter.backup_last_saved_at", "-")
        }
        return sb.toString()
    }

    private fun exitReason(code: Int): String = when (code) {
        1 -> "EXIT_SELF"
        2 -> "SIGNALED"
        3 -> "LOW_MEMORY"
        4 -> "CRASH"
        5 -> "CRASH_NATIVE"
        6 -> "ANR"
        7 -> "INITIALIZATION_FAILURE"
        8 -> "PERMISSION_CHANGE"
        9 -> "EXCESSIVE_RESOURCE_USAGE"
        10 -> "USER_REQUESTED"
        11 -> "USER_STOPPED"
        12 -> "DEPENDENCY_DIED"
        13 -> "OTHER"
        14 -> "FREEZER"
        15 -> "PACKAGE_STATE_CHANGE"
        16 -> "PACKAGE_UPDATED"
        else -> "UNKNOWN($code)"
    }

    /** 이 알람 ID의 기상 예약이 OS에 실제로 걸려 있는지(AlarmWakeScheduler.scheduleRaw와 같은 PendingIntent로 확인). */
    fun isRegistered(context: Context, id: Int): Boolean {
        val intent = Intent(context, CustomAlarmReceiver::class.java).apply {
            data = Uri.parse("shiftbell://alarm/$id")
        }
        return PendingIntent.getBroadcast(context, id, intent, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE) != null
    }

    /**
     * 파일로 저장하고 content URI를 돌려줌(Android 10 미만·실패 시 null). 이 설치본이 만든 이전 진단 파일은 지움(항상 1개).
     */
    fun export(context: Context): Uri? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val content = buildSnapshot(context) + "\n=== 기록(오래된 것 → 최근) ===\n" + DiagLog.readAll(context)
        val resolver = context.contentResolver
        val name = prefix(context) + SimpleDateFormat("yyMMdd_HHmmss", Locale.US).format(Date()) + ".txt"
        return try {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                put(MediaStore.Downloads.RELATIVE_PATH, RELATIVE_PATH)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return null
            resolver.openOutputStream(uri)?.use { it.write(content.toByteArray(Charsets.UTF_8)) }
                ?: run { resolver.delete(uri, null, null); return null }
            resolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
            deleteOthers(context, ContentUris.parseId(uri))
            DiagLog.log(context, "DIAG_EXPORTED", "bytes" to content.length)
            uri
        } catch (e: Exception) {
            Log.e(TAG, "진단 파일 저장 실패", e)
            null
        }
    }

    private fun deleteOthers(context: Context, keepId: Long) {
        try {
            val resolver = context.contentResolver
            val pre = prefix(context)
            val ids = mutableListOf<Long>()
            resolver.query(MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.Downloads._ID, MediaStore.Downloads.DISPLAY_NAME), null, null, null)?.use { c ->
                while (c.moveToNext()) {
                    val n = c.getString(1) ?: continue
                    val isOurs = n.startsWith(pre) && (pre.endsWith("_dev_") || !n.startsWith("ShiftBell_Diag_dev_"))
                    if (isOurs && c.getLong(0) != keepId) ids += c.getLong(0)
                }
            }
            for (id in ids) resolver.delete(ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, id), null, null)
        } catch (e: Exception) {
            Log.w(TAG, "이전 진단 파일 정리 실패(무시)", e)
        }
    }

    /** 공유 시트(카카오톡·메일 등). */
    fun share(context: Context, uri: Uri, chooserTitle: String) {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, "ShiftBell 진단 파일")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(send, chooserTitle).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

}
