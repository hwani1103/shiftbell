package com.hwani1103.shiftbell

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.ByteArrayInputStream

// 2026-09-22 (B-1) - 백업 파일 읽기 크기 상한.
class BackupFileReaderTest {
    @Test
    fun `상한 이하는 그대로 읽는다 - 한글 포함`() {
        val json = """{"schemaVersion":1,"tables":{"date_memos":[{"content":"야간 전 낮잠"}]}}"""
        val bytes = json.toByteArray(Charsets.UTF_8)
        assertEquals(json, BackupFileReader.readBoundedUtf8(ByteArrayInputStream(bytes), bytes.size.toLong()))
    }

    @Test
    fun `상한을 1바이트라도 넘으면 null`() {
        val bytes = ByteArray(1001) { 'a'.code.toByte() }
        assertNull(BackupFileReader.readBoundedUtf8(ByteArrayInputStream(bytes), 1000))
    }

    @Test
    fun `버퍼보다 큰 정상 파일도 끝까지 읽는다`() {
        val text = "가".repeat(100_000) // UTF-8 300KB, 내부 버퍼(64KB)의 여러 배
        val bytes = text.toByteArray(Charsets.UTF_8)
        assertEquals(text, BackupFileReader.readBoundedUtf8(ByteArrayInputStream(bytes)))
    }
}
