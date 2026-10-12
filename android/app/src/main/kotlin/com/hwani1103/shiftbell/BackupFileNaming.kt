package com.hwani1103.shiftbell

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * ⭐ 2026-09-23 (1.0.24 A) - 백업 파일을 "직접 백업 1개 + 자동 백업 1개" 두 슬롯으로 관리하기 위한 파일명 규칙.
 *
 *  - 새 형식: `{prefix}manual_yyMMdd_HHmmss.json` / `{prefix}auto_yyMMdd_HHmmss.json`
 *    (prefix = "ShiftBell_Backup_" 또는 dev의 "ShiftBell_Backup_dev_"). 초까지 넣어 같은 분에 두 번 써도
 *    MediaStore가 "(1)"을 붙이지 않게 함.
 *  - 옛 형식(1.0.23 이하): `{prefix}yyMMdd_HHmm.json`, `{prefix}yyMMdd.json`, 그리고 MediaStore가 붙인 "… (1).json" 변형.
 *    종류 구분이 없어서 [Kind.LEGACY]로 분류하고, 새 형식 자동 백업이 처음 성공한 뒤 정리함.
 *
 * MediaStore·Context에 의존하지 않는 순수 함수만 둬서 JVM 단위 테스트로 고정한다(BackupFileNamingTest).
 */
object BackupFileNaming {
    enum class Kind(val token: String) {
        MANUAL("manual"),
        AUTO("auto"),
        LEGACY("");

        companion object {
            /** 채널 인자("manual"/"auto") → Kind. 알 수 없는 값은 자동 백업으로 취급(더 안전한 쪽 - 직접 백업 슬롯을 덮지 않음). */
            fun fromChannelArg(arg: String?): Kind = if (arg == MANUAL.token) MANUAL else AUTO
        }
    }

    fun displayName(prefix: String, kind: Kind, now: Date = Date()): String {
        require(kind != Kind.LEGACY) { "새 백업은 manual/auto로만 씀" }
        val stamp = SimpleDateFormat("yyMMdd_HHmmss", Locale.US).format(now)
        return "$prefix${kind.token}_$stamp.json"
    }

    /**
     * 파일명이 이 설치본의 백업인지, 어느 슬롯인지. 백업이 아니면 null.
     * ⚠️ prod prefix("ShiftBell_Backup_")는 dev 파일명("ShiftBell_Backup_dev_…")의 앞부분과도 겹치므로
     * prod에서는 "dev_"로 이어지는 이름을 제외한다(원래는 소유권 때문에 보이지 않지만 방어적으로).
     */
    fun classify(prefix: String, name: String): Kind? {
        if (!name.startsWith(prefix)) return null
        val rest = name.substring(prefix.length)
        if (!prefix.endsWith("_dev_") && rest.startsWith("dev_")) return null
        return when {
            rest.startsWith("${Kind.MANUAL.token}_") -> Kind.MANUAL
            rest.startsWith("${Kind.AUTO.token}_") -> Kind.AUTO
            rest.isNotEmpty() && rest[0].isDigit() -> Kind.LEGACY
            else -> null
        }
    }

    /**
     * 새 백업을 쓴 뒤 지울 파일 ID 목록.
     *  - 같은 종류([written])의 다른 파일은 전부 삭제(슬롯당 1개).
     *  - 자동 백업을 썼을 때만 옛 형식(LEGACY) 파일도 삭제(1.0.23 → 1.0.24 이관, 결정 6). 직접 백업만 한 상태에서는
     *    옛 파일이 유일한 자동 백업 대용일 수 있으므로 남긴다.
     *  - 다른 종류의 파일은 절대 건드리지 않음(자동 백업이 직접 백업을 지우면 안 됨).
     */
    fun idsToDelete(prefix: String, written: Kind, newId: Long, files: List<Pair<Long, String>>): List<Long> =
        files.filter { (id, name) ->
            if (id == newId) return@filter false
            when (classify(prefix, name)) {
                written -> true
                Kind.LEGACY -> written == Kind.AUTO
                else -> false
            }
        }.map { it.first }
}
