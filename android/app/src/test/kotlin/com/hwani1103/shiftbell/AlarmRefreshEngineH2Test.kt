// android/app/src/test/kotlin/com/hwani1103/shiftbell/AlarmRefreshEngineH2Test.kt
//
// 테스트_계획_2026-09-12.md B-2 대상 #1 — "AlarmRefreshEngine.doRefresh() - toAdd
// 배치 중 N번째 항목에서 scheduleNativeAlarm()이 예외를 던지도록 mock → 그 이전
// 항목들의 DB 상태/OS 등록 상태가 의도대로 되는지(H2 관련 검증용 - 지금은 안
// 고치기로 했지만, 나중에 고치기로 결정하면 이 테스트가 바로 '제대로 고쳐졌는지
// 100% 검증' 역할을 함)".
//
// H2(전체_코드_점검_리포트_2026-09-04.md)는 "알람 갱신 트랜잭션 중 OS 콜" 문제 -
// doRefresh()의 toAdd 삽입 루프가 db.beginTransaction()/endTransaction() 안에서
// scheduleNativeAlarm()(실제 OS AlarmManager 호출)을 직접 부르는데, 이 OS 호출이
// 예외를 던지면 그 예외가 트랜잭션 블록 밖으로 그대로 전파되어 db.setTransactionSuccessful()이
// 호출되지 못하고, endTransaction()이 "이전에 이미 정상적으로 insert된 항목들까지
// 포함해서" 전체를 롤백해버린다. 즉 1번째~(N-1)번째 알람은 OS 등록이 이미
// 끝났을 수도 있는데 DB에는 그 사실이 하나도 안 남는 상태가 될 수 있음.
//
// 이 테스트는 그 현재 동작(고치기로 결정하기 전까지의 "있는 그대로")을 characterization
// test로 고정해둔다 - assertion을 뒤집지 않고 그대로 두면, 나중에 H2를 실제로 고쳤을 때
// (예: 각 항목을 개별 트랜잭션으로 쪼개거나, OS 호출 실패를 흡수하고 계속 진행하도록
// 바꾸면) 이 테스트가 즉시 실패하게 되어 "의도한 대로 고쳐졌는지"를 알려준다.
//
// ⚠️ 실제 프로덕션 DB 스키마 전체를 복제하지 않고, doRefresh()가 실제로 읽고/쓰는
// 컬럼만 최소로 구성한 픽스처를 씀. 픽스처는 반드시 DatabaseHelper.getInstance(context)가
// 내부적으로 여는 것과 "같은" SQLiteDatabase 연결 위에서 만들어야 한다 - 별도의
// 원시 SQLiteDatabase.openOrCreateDatabase() 연결로 파일만 미리 만들고 닫는 방식은
// Robolectric의 sqlite4java 셰도우에서 "Illegal connection pointer"/"database is
// locked" 오류로 실패함(2026-09-12, 인프라 구축 중 실제로 겪은 문제) - 그래서
// dbHelper.writableDatabase를 먼저 한 번 호출해 SQLiteOpenHelper가 파일을 만들고
// version을 자동으로 DATABASE_VERSION에 맞추게 한 뒤, 그 동일 연결 위에서 테이블을
// 만들고 데이터를 넣는다.
package com.hwani1103.shiftbell

import android.content.ContentValues
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.concurrent.atomic.AtomicInteger

@RunWith(RobolectricTestRunner::class)
class AlarmRefreshEngineH2Test {

    private val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault())

    private lateinit var context: Context
    private lateinit var dbHelper: DatabaseHelper

    // ⭐ DAYS_AHEAD(=10)만큼 매일 "주간" 알람을 만들지만, 실행 시각에 따라 "오늘"
    // 07:00이 이미 지났을 수도 있어(addFrom()의 "이미 지난 시각은 스킵" 규칙) 정확히
    // 10개가 보장되지 않음 - 최소 9개(오늘 하루를 빼더라도)는 항상 보장됨. 정확한 값
    // 대신 이 하한선으로 픽스처 유효성을 확인해 시각에 따른 flaky를 피한다.
    private val minExpectedAlarms = 9

    @Before
    fun setUp() {
        // ⭐ 이전 테스트 메서드가 남긴 낡은 싱글턴(무효화된 커넥션 포인터)을 정리 -
        // DatabaseHelper.resetInstanceForTest() 주석 참고.
        DatabaseHelper.resetInstanceForTest()
        context = ApplicationProvider.getApplicationContext()
        dbHelper = DatabaseHelper.getInstance(context)
        seedMinimalDatabase()
    }

    @After
    fun tearDown() {
        DatabaseHelper.resetInstanceForTest()
    }

    private fun seedMinimalDatabase() {
        // ⭐ 2026-09-14 (G0, T03) - 예전엔 여기서 dbHelper.writableDatabase를 먼저 불러 SQLiteOpenHelper가
        // 빈 파일을 만들고 onCreate(no-op) 후 버전을 찍게 한 뒤 테이블을 만들었음. G0에서 Native onCreate가
        // 예외로 바뀌어(빈 최신 버전 DB 생성 차단, 출시전 감사 #1) 그 방식은 더 이상 동작하지 않음.
        // → 같은 최소 스키마를 user_version=24로 미리 만들어 둔 파일(tool/g0/build_fixtures.py가 생성)을
        // 복사한 뒤 헬퍼로 연다. 원시 연결로 파일을 만드는 방식은 위 주석의 Robolectric 연결 오류 때문에 피함.
        // 버전이 이미 24라 마이그레이션은 없음. 단 Gradle 단위 테스트에는 flutter 자산이 합쳐져 들어가서
        // onOpen repair가 실제 SQL 원본으로 돌아, 이 최소 스키마에 없는 테이블/컬럼(기본값 NULL 또는 0)을
        // 추가함 - 이 테스트가 쓰는 컬럼과 값에는 영향 없음(T03 실행으로 확인).
        val dbFile = context.applicationContext.createDeviceProtectedStorageContext().getDatabasePath("shiftbell.db")
        for (suffix in listOf("", "-wal", "-shm", "-journal")) java.io.File(dbFile.path + suffix).delete()
        dbFile.parentFile?.mkdirs()
        java.io.File(G0TestSupport.g0Dir, "fixtures_db/aux_h2_minimal_v24.db").copyTo(dbFile, overwrite = true)
        val db = dbHelper.writableDatabase

        // 매일 "주간"만 반복되는 규칙적 패턴(패턴 길이 1) - 매일이 전부 "주간"이 되어
        // toAdd에 (오늘 07:00이 이미 지났으면 9개, 아니면 10개가) 들어감.
        val startDate = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

        db.insert("shift_schedule", null, ContentValues().apply {
            put("is_regular", 1)
            put("pattern", "주간")
            put("today_index", 0)
            put("start_date", dateFormat.format(startDate.time))
            put("assigned_dates", null as String?)
        })
        db.insert("shift_alarm_templates", null, ContentValues().apply {
            put("shift_type", "주간")
            put("time", "07:00")
            put("alarm_type_id", 1)
            put("day_offset", 0)
        })
    }

    private fun countAlarmRows(): Int {
        dbHelper.writableDatabase.rawQuery("SELECT COUNT(*) FROM alarms", null).use { cursor ->
            cursor.moveToFirst()
            return cursor.getInt(0)
        }
    }

    @Test
    fun `대조군 - 아무 것도 실패하지 않으면 매일 알람이 정상 삽입된다`() {
        AlarmRefreshEngine.doRefresh(context, scheduleNativeAlarmOverride = { _, _, _, _, _ -> /* 성공한 척 */ })
        val count = countAlarmRows()
        assertTrue(
            "픽스처가 올바르면 최소 ${minExpectedAlarms}일치가 삽입돼야 함(=$count) - 0이면 " +
                "DB 버전/경로 불일치로 doRefresh가 조용히 스킵했다는 뜻(테스트 자체의 문제)",
            count >= minExpectedAlarms
        )
    }

    @Test
    fun `H2 - N번째 항목에서 OS 알람 등록이 실패하면 이전 항목들의 DB insert까지 통째로 롤백된다`() {
        val callCount = AtomicInteger(0)
        val failAtNth = 3

        var thrown: Throwable? = null
        try {
            AlarmRefreshEngine.doRefresh(
                context,
                scheduleNativeAlarmOverride = { _, _, _, _, _ ->
                    if (callCount.incrementAndGet() == failAtNth) {
                        throw RuntimeException("가짜 OS 알람 등록 실패 (예: SecurityException 등을 흉내)")
                    }
                }
            )
        } catch (e: Throwable) {
            thrown = e
        }

        assertTrue("scheduleNativeAlarm 실패는 doRefresh 밖으로 예외를 그대로 전파해야 함(현재 동작)", thrown != null)
        assertTrue(
            "픽스처가 최소 ${minExpectedAlarms}개를 만들어야 N번째(=$failAtNth)에 도달 가능한데 " +
                "실제로는 ${callCount.get()}번만 호출됨 - 픽스처 문제일 수 있음",
            callCount.get() >= failAtNth
        )

        // ⭐ H2의 핵심 증상: 1~(N-1)번째는 db.insert()가 이미 성공했었는데도,
        // 트랜잭션 전체가 롤백되어 DB에는 단 한 건도 안 남는다.
        val countAfterFailure = countAlarmRows()
        assertEquals(
            "H2 미수정 상태의 현재 동작 - 트랜잭션 전체 롤백으로 1~${failAtNth - 1}번째 항목의 " +
                "insert까지 전부 사라짐. 이 값이 0이 아니게 바뀌면(예: ${failAtNth - 1}) H2가 " +
                "고쳐졌다는 뜻이니 이 assertion을 그 고친 내용에 맞게 업데이트할 것.",
            0,
            countAfterFailure
        )
    }
}
