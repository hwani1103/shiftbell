package com.hwani1103.shiftbell

import java.io.ByteArrayOutputStream
import java.io.InputStream

/**
 * ⭐ 2026-09-22 (출시 전 품질점검 B-1) - 백업 파일 읽기의 크기 상한.
 *
 * 예전엔 파일 선택기(SAF)로 고른 파일을 readBytes()로 통째로 읽었다. 선택기는 백업이 목록에 안 보이던 문제 때문에
 * 일부러 모든 파일 형식을 열어 두었으므로(MainActivity "pickBackupFile" 주석), 동영상처럼 큰 파일을 잘못 고르면
 * 메모리 부족으로 앱이 죽을 수 있었다. 상한을 넘으면 읽지 않고 null(= 지금처럼 "백업 파일이 아님" 안내)로 처리한다.
 *
 * 16MB 근거: 백업에서 계속 커지는 것은 영구 보존 이력 두 테이블(alarm_history, alarm_creation_log)뿐이고, 하루 알람
 * 5개 기준 1년에 1MB 안팎이다. 수십 년치 여유가 있으면서, 문자열 사본 + Dart 디코딩까지 메모리에 안전한 크기.
 * ⚠️ 쓰기(saveBackupToDownloads)는 이 값을 넘어도 절대 막지 않는다 - 백업이 안 만들어지는 게 더 나쁘다(경고 로그만).
 */
object BackupFileReader {
    const val MAX_BACKUP_BYTES: Long = 16L * 1024 * 1024

    /** [maxBytes]까지만 읽어 UTF-8 문자열로 돌려준다. 넘치면 나머지를 읽지 않고 null. */
    fun readBoundedUtf8(input: InputStream, maxBytes: Long = MAX_BACKUP_BYTES): String? {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            total += n
            if (total > maxBytes) return null
            out.write(buffer, 0, n)
        }
        return out.toString(Charsets.UTF_8.name())
    }
}
