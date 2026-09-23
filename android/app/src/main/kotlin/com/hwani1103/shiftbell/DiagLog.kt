package com.hwani1103.shiftbell

import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * ⭐ 2026-09-23 (1.0.24 C) - 문제 진단 기록. 사용자가 "알람이 안 울렸어요/백업이 안 돼요"라고 알려올 때,
 * 설정의 "문제 신고용 진단 파일 만들기"로 내보낸 파일 하나로 **권한 / 제조사·OS 백그라운드 제한 / 앱 코드 결함**을 가르기 위함.
 * 해석 방법은 docs/진단로그_해석_매뉴얼.md(이벤트 이름 ↔ 이 파일을 부르는 소스 위치 표 포함).
 *
 * 규칙
 *  - **기기 안에만** 기록(Device Protected 저장소 → 잠금 해제 전 알람 경로에서도 기록 가능). 외부 전송은 사용자가 직접 내보낼 때뿐.
 *  - 파일 2개(diag_0.log/diag_1.log)를 번갈아 씀. 쓰는 파일이 [MAX_FILE_BYTES]를 넘으면 다른 파일을 비우고 넘어감 → 총 약 512KB 상한.
 *  - 한 줄 형식: `2026-09-23T06:59:58.120+0900 | EVENT | key=value key=value`
 *  - **기록 금지**: 메모·일정 내용, 근무명, 친구 이름, 공유 코드. 알람은 ID·시각·종류만.
 *  - 쓰기 실패는 삼킴 - 진단 기록 때문에 알람·백업이 실패하면 안 됨.
 */
object DiagLog {
    private const val TAG = "DiagLog"
    internal const val MAX_FILE_BYTES = 256L * 1024
    private const val DIR = "diag"
    private val lock = Any()

    /** 테스트에서 시계 고정용. */
    @Volatile internal var clock: () -> Long = { System.currentTimeMillis() }

    private fun dir(context: Context): File {
        val base = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.createDeviceProtectedStorageContext()
        } else context
        return File(base.filesDir, DIR).apply { mkdirs() }
    }

    internal fun files(context: Context): Pair<File, File> {
        val d = dir(context)
        return File(d, "diag_0.log") to File(d, "diag_1.log")
    }

    /** 값 안의 줄바꿈·구분자는 공백으로 - 한 이벤트가 항상 한 줄이 되게. */
    private fun clean(v: Any?): String = v?.toString()?.replace(Regex("[\\r\\n|]"), " ")?.take(200) ?: "null"

    fun format(at: Long, event: String, fields: List<Pair<String, Any?>>): String {
        val ts = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US).format(Date(at))
        val kv = fields.joinToString(" ") { (k, v) -> "$k=${clean(v)}" }
        return if (kv.isEmpty()) "$ts | $event" else "$ts | $event | $kv"
    }

    fun log(context: Context, event: String, vararg fields: Pair<String, Any?>) {
        try {
            val line = format(clock(), event, fields.toList()) + "\n"
            synchronized(lock) {
                val (a, b) = files(context)
                // 더 최근에 쓴 파일이 현재 파일. 넘치면 다른 파일을 비우고 그쪽으로.
                var current = if (b.exists() && (!a.exists() || b.lastModified() > a.lastModified())) b else a
                if (current.exists() && current.length() + line.length > MAX_FILE_BYTES) {
                    current = if (current == a) b else a
                    current.writeText("")
                }
                current.appendText(line)
                // 같은 밀리초 안에 두 파일이 바뀌어도 순서가 흔들리지 않게 현재 파일 시각을 명시
                current.setLastModified(maxOf(clock(), (if (current == a) b else a).lastModified() + 1))
            }
        } catch (e: Exception) {
            Log.w(TAG, "진단 기록 실패(무시): $event", e)
        }
    }

    /** 두 파일을 오래된 것 → 최근 것 순서로 이어 붙인 전체 기록. */
    fun readAll(context: Context): String = try {
        synchronized(lock) {
            val (a, b) = files(context)
            listOf(a, b).filter { it.exists() }.sortedBy { it.lastModified() }.joinToString("") { it.readText() }
        }
    } catch (e: Exception) {
        "(진단 기록을 읽지 못함: ${e.message})\n"
    }
}
