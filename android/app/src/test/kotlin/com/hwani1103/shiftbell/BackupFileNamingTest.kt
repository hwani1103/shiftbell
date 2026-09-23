package com.hwani1103.shiftbell

import com.hwani1103.shiftbell.BackupFileNaming.Kind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

/** 1.0.24 A - 백업 두 슬롯(직접/자동) 파일명·정리 규칙. */
class BackupFileNamingTest {
    private val prod = "ShiftBell_Backup_"
    private val dev = "ShiftBell_Backup_dev_"

    private fun at(y: Int, mo: Int, d: Int, h: Int, mi: Int, s: Int) =
        Calendar.getInstance().apply { set(y, mo - 1, d, h, mi, s); set(Calendar.MILLISECOND, 0) }.time

    @Test
    fun displayName_hasKindAndSeconds() {
        assertEquals("ShiftBell_Backup_manual_260923_224605.json",
            BackupFileNaming.displayName(prod, Kind.MANUAL, at(2026, 9, 23, 22, 46, 5)))
        assertEquals("ShiftBell_Backup_dev_auto_260923_224659.json",
            BackupFileNaming.displayName(dev, Kind.AUTO, at(2026, 9, 23, 22, 46, 59)))
    }

    @Test
    fun classify_newLegacyAndForeign() {
        assertEquals(Kind.MANUAL, BackupFileNaming.classify(prod, "ShiftBell_Backup_manual_260923_224605.json"))
        assertEquals(Kind.AUTO, BackupFileNaming.classify(prod, "ShiftBell_Backup_auto_260923_224605 (1).json"))
        assertEquals(Kind.LEGACY, BackupFileNaming.classify(prod, "ShiftBell_Backup_260923_2246.json"))
        assertEquals(Kind.LEGACY, BackupFileNaming.classify(prod, "ShiftBell_Backup_260923_2246(1).json"))
        assertEquals(Kind.LEGACY, BackupFileNaming.classify(prod, "ShiftBell_Backup_260917.json"))
        // prod는 dev 파일을 자기 것으로 보지 않음
        assertNull(BackupFileNaming.classify(prod, "ShiftBell_Backup_dev_auto_260923_224605.json"))
        assertNull(BackupFileNaming.classify(prod, "ShiftBell_Backup_dev_260923_2246.json"))
        assertEquals(Kind.AUTO, BackupFileNaming.classify(dev, "ShiftBell_Backup_dev_auto_260923_224605.json"))
        assertEquals(Kind.LEGACY, BackupFileNaming.classify(dev, "ShiftBell_Backup_dev_260923_2246.json"))
        assertNull(BackupFileNaming.classify(prod, "other.json"))
        assertNull(BackupFileNaming.classify(prod, "ShiftBell_Diag_260923_224605.txt"))
    }

    private val files = listOf(
        1L to "ShiftBell_Backup_260923_1503.json",          // 옛 형식
        2L to "ShiftBell_Backup_260923_2246(1).json",       // 옛 형식
        3L to "ShiftBell_Backup_manual_260923_100000.json", // 옛 직접
        4L to "ShiftBell_Backup_auto_260923_110000.json",   // 옛 자동
        5L to "ShiftBell_Backup_manual_260923_120000.json", // 방금 쓴 직접
        6L to "ShiftBell_Backup_auto_260923_130000.json",   // 방금 쓴 자동
        7L to "unrelated.pdf",
    )

    @Test
    fun manualWrite_deletesOnlyOtherManual() {
        assertEquals(listOf(3L), BackupFileNaming.idsToDelete(prod, Kind.MANUAL, 5L, files))
    }

    @Test
    fun autoWrite_deletesOtherAutoAndLegacy_neverManual() {
        val ids = BackupFileNaming.idsToDelete(prod, Kind.AUTO, 6L, files)
        assertEquals(listOf(1L, 2L, 4L), ids)
        assertTrue(3L !in ids && 5L !in ids && 7L !in ids)
    }

    @Test
    fun channelArg_defaultsToAuto() {
        assertEquals(Kind.MANUAL, Kind.fromChannelArg("manual"))
        assertEquals(Kind.AUTO, Kind.fromChannelArg("auto"))
        assertEquals(Kind.AUTO, Kind.fromChannelArg(null))
        assertEquals(Kind.AUTO, Kind.fromChannelArg("weird"))
    }
}
