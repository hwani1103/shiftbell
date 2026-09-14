// android/app/src/test/kotlin/com/hwani1103/shiftbell/G0NativeMigrationTest.kt
//
// G0(T03) Native(DatabaseHelper + DbMigrationRunner) 마이그레이션 검증 - Robolectric 실제 SQLite.
// 케이스 이름은 T01 expected.md 표를 따르고, 구조 기준은 Dart _onCreate로 만든 v24_oncreate_schema.json.
// 제품과 같은 진입점(DatabaseHelper.getWritableDatabaseWithRetry → 게이트 → SQLiteOpenHelper open)을 쓴다.
// Robolectric엔 flutter_assets가 없으므로 SQL 원본은 저장소 assets/db/migrations.json을 overrideForTest로 주입.
package com.hwani1103.shiftbell

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

@RunWith(RobolectricTestRunner::class)
class G0NativeMigrationTest {

    private lateinit var context: Context
    private lateinit var dbFile: File
    private val reference: JSONObject by lazy { JSONObject(G0TestSupport.readG0("v24_oncreate_schema.json")) }

    @Before
    fun setUp() {
        DatabaseHelper.resetInstanceForTest()
        context = ApplicationProvider.getApplicationContext()
        // DatabaseHelper.getInstance와 같은 Context 경로
        dbFile = context.applicationContext.createDeviceProtectedStorageContext().getDatabasePath("shiftbell.db")
        useScript(G0TestSupport.repoScriptJson())
    }

    @After
    fun tearDown() {
        DatabaseHelper.resetInstanceForTest()
        DbMigrationScript.overrideForTest = null
        deleteDbFiles()
    }

    private fun useScript(json: String) {
        DbMigrationScript.overrideForTest = DbMigrationScript.parse(json)
    }

    private fun mutatedScript(mutation: String): String =
        G0TestSupport.applyMutation(JSONObject(G0TestSupport.repoScriptJson()), JSONObject(mutation)).toString()

    private fun deleteDbFiles() {
        for (suffix in listOf("", "-wal", "-shm", "-journal")) File(dbFile.path + suffix).delete()
    }

    private fun installFixture(name: String) {
        DatabaseHelper.resetInstanceForTest()
        deleteDbFiles()
        dbFile.parentFile?.mkdirs()
        File(G0TestSupport.g0Dir, "fixtures_db/$name").copyTo(dbFile, overwrite = true)
    }

    private fun helper(): DatabaseHelper = DatabaseHelper.getInstance(context)

    /** 헬퍼를 닫은 뒤, 버전 확인·마이그레이션 없이 파일 상태를 본다. */
    private fun <T> withRaw(block: (SQLiteDatabase) -> T): T {
        DatabaseHelper.resetInstanceForTest()
        val db = SQLiteDatabase.openDatabase(dbFile.path, null, SQLiteDatabase.OPEN_READWRITE)
        try {
            return block(db)
        } finally {
            db.close()
        }
    }

    private fun schemaCanonical(db: SQLiteDatabase) = G0TestSupport.canonical(G0TestSupport.schemaSnapshot(db))
    private fun dataCanonical(db: SQLiteDatabase) = G0TestSupport.canonical(G0TestSupport.dumpTables(db))
    private fun expected(name: String) = JSONObject(G0TestSupport.readG0("expected_v24/$name"))

    @Test
    fun migAll_reopen_v1toV23_matchExpectedDataAndReferenceSchema() {
        val fixtures = G0TestSupport.fixtureIndex()
        assertEquals("fixture 개수", 23, fixtures.size)
        val failures = ArrayList<String>()
        for (fx in fixtures) {
            val dbName = fx.getString("db")
            try {
                installFixture(dbName)
                val db = helper().getWritableDatabaseWithRetry()
                if (db == null) {
                    failures.add("$dbName: getWritableDatabaseWithRetry() == null")
                    continue
                }
                val problems = ArrayList<String>()
                if (db.version != 24) problems.add("user_version=${db.version}")
                val data = G0TestSupport.dumpTables(db)
                problems += G0TestSupport.diffExpectedData(data, expected(fx.getString("expected")))
                if (schemaCanonical(db) != G0TestSupport.canonical(reference)) {
                    problems.add("schema != v24_oncreate_schema.json\n    actual: ${schemaCanonical(db)}")
                }
                expectOverridesConstraints(db)

                DatabaseHelper.resetInstanceForTest()
                val again = helper().getWritableDatabaseWithRetry()
                if (again == null) problems.add("두 번째 open null")
                else if (G0TestSupport.canonical(G0TestSupport.dumpTables(again)) != G0TestSupport.canonical(data)) {
                    problems.add("두 번째 open에서 데이터 변화")
                }
                if (problems.isNotEmpty()) failures.add("$dbName (start v${fx.getInt("start_version")}):\n  ${problems.joinToString("\n  ")}")
            } catch (e: Throwable) {
                failures.add("$dbName: 예외 $e\n${e.stackTraceToString()}")
            }
        }
        assertTrue(failures.joinToString("\n\n"), failures.isEmpty())
    }

    @Test
    fun rollback_v12_failureAtV20_restoresEverything_thenRetrySucceeds() {
        installFixture("v12.db")
        val (beforeSchema, beforeData) = withRaw { schemaCanonical(it) to dataCanonical(it) }

        useScript(mutatedScript("""{"migration_append": {"version": 20, "sql": "CREATE TABLE alarm_types(x INTEGER)"}}"""))
        assertNull("실패 주입 시 DB를 내주면 안 됨", helper().getWritableDatabaseWithRetry())

        withRaw {
            assertEquals(12, it.version)
            assertEquals(beforeSchema, schemaCanonical(it))
            assertEquals(beforeData, dataCanonical(it))
        }

        useScript(G0TestSupport.repoScriptJson())
        val db = helper().getWritableDatabaseWithRetry()
        assertNotNull(db)
        assertEquals(24, db!!.version)
        assertEquals(emptyList<String>(), G0TestSupport.diffExpectedData(G0TestSupport.dumpTables(db), expected("v12.json")))
    }

    @Test
    fun friendRollback_v16_failureAfterV17Drop_restoresOldFriends() {
        installFixture("v16.db")
        useScript(mutatedScript("""{"migration_insert_after": {"version": 17, "index": 1, "sql": "CREATE TABLE friends(x INTEGER)"}}"""))
        assertNull(helper().getWritableDatabaseWithRetry())
        withRaw { raw ->
            assertEquals(16, raw.version)
            val cols = G0TestSupport.query(raw, "PRAGMA table_info(friends)").map { it["name"] }.toSet()
            assertTrue(cols.toString(), "has_memos" in cols && "owner_id" !in cols)
            assertEquals(listOf(701L), G0TestSupport.query(raw, "SELECT id FROM friends").map { it["id"] })
        }
    }

    @Test
    fun missingColumn_stamped24_repairFillsSchema_keepsData() {
        installFixture("variant_v23_stamped24_missing.db")
        val db = helper().getWritableDatabaseWithRetry()
        assertNotNull(db)
        assertEquals(24, db!!.version)
        assertEquals(G0TestSupport.canonical(reference), schemaCanonical(db))
        assertEquals(
            emptyList<String>(),
            G0TestSupport.diffExpectedData(G0TestSupport.dumpTables(db), expected("variant_v23_stamped24_missing.json"))
        )
    }

    @Test
    fun alterFail_repair_propagates_andRollsBackOtherRepairs() {
        installFixture("variant_v23_stamped24_missing.db")
        useScript(mutatedScript("""{"replace_repair": {"from": "ALTER TABLE date_schedules ADD COLUMN notify_offset_minutes INTEGER NOT NULL DEFAULT 0", "to": "ALTER TABLE date_schedules ADD COLUMN notify_offset_minutes INTEGER NOT NULL"}}"""))
        assertNull(helper().getWritableDatabaseWithRetry())
        withRaw { raw ->
            val cols = G0TestSupport.query(raw, "PRAGMA table_info(date_schedules)").map { it["name"] }.toSet()
            assertFalse("notify_offset_minutes" in cols)
            assertTrue(
                "실패한 repair 트랜잭션의 CREATE TABLE도 롤백돼야 함",
                G0TestSupport.query(raw, "SELECT name FROM sqlite_master WHERE type='table' AND name='alarm_overrides'").isEmpty()
            )
            assertEquals(24, raw.version)
        }
    }

    @Test
    fun alterFail_migration_missingTable_isNotSkipped() {
        installFixture("v18.db")
        useScript(mutatedScript("""{"migration_append": {"version": 19, "sql": "ALTER TABLE no_such_table ADD COLUMN day_offset INTEGER NOT NULL DEFAULT 0"}}"""))
        assertNull(helper().getWritableDatabaseWithRetry())
        withRaw { assertEquals(18, it.version) }
    }

    @Test
    fun futureVersion_25_gateSkips_andOnDowngradeThrows_versionAndDataUnchanged() {
        installFixture("variant_v23_stamped25.db")
        val before = withRaw { dataCanonical(it) }
        assertNull(helper().getWritableDatabaseWithRetry())
        try {
            helper().writableDatabase
            fail("다운그레이드는 예외여야 함")
        } catch (e: DbMigrationException) {
            // 기대
        }
        withRaw {
            assertEquals(25, it.version)
            assertEquals(before, dataCanonical(it))
        }
    }

    @Test
    fun versionZero_existingFile_nativeDoesNotCreateSchema() {
        installFixture("variant_empty_v0.db")
        assertNull(helper().getWritableDatabaseWithRetry())
        try {
            helper().writableDatabase
            fail("Native onCreate는 예외여야 함")
        } catch (e: DbMigrationException) {
            // 기대
        }
        withRaw {
            assertEquals(0, it.version)
            assertEquals("{}", schemaCanonical(it).let { s -> if (s == "{}") s else s })
        }
    }

    @Test
    fun nativeNew_noFile_returnsNull_andDoesNotCreateFile() {
        DatabaseHelper.resetInstanceForTest()
        deleteDbFiles()
        assertNull(helper().getWritableDatabaseWithRetry())
        assertNull(helper().getReadableDatabaseWithRetry())
        assertFalse("Native가 DB 파일을 만들면 안 됨", dbFile.exists())
    }

    // ⭐ T03 1차 실행에서 확인: Gradle testDevDebugUnitTest는 copyFlutterAssetsDevDebug로 flutter 자산을
    // 합쳐 넣고 isIncludeAndroidResources=true라서, Robolectric에서도 AssetManager로
    // flutter_assets/assets/db/migrations.json이 읽힌다. 그래서 "자산 누락" 상황은 주입 지점이 없어
    // 이 테스트로 재현할 수 없음(test_results.md에 NOT_RUN) - 대신 제품 경로의 자산 읽기를 검증한다.
    // (debug merge 기준. release APK·첫 잠금 해제 전 읽기는 실기기 S1에서만 확인 가능)
    @Test
    fun assetPath_nativeLoadsSameScriptAsRepo_andUpgradesWithoutOverride() {
        DbMigrationScript.overrideForTest = null
        val fromAsset = DbMigrationScript.load(context)
        val fromRepo = DbMigrationScript.parse(G0TestSupport.repoScriptJson())
        assertEquals(fromRepo.targetVersion, fromAsset.targetVersion)
        assertEquals(fromRepo.migrations, fromAsset.migrations)
        assertEquals(fromRepo.repair, fromAsset.repair)

        installFixture("v18.db")
        val db = helper().getWritableDatabaseWithRetry()
        assertNotNull("자산 원본으로 v18 → v24", db)
        assertEquals(24, db!!.version)
        assertEquals(emptyList<String>(), G0TestSupport.diffExpectedData(G0TestSupport.dumpTables(db), expected("v18.json")))
        println("G0 Robolectric sqlite_version=" + G0TestSupport.query(db, "SELECT sqlite_version() AS v").first()["v"])
    }

    @Test
    fun onUpgrade_rereadsVersionInsideLock() {
        installFixture("v23.db")
        val db = helper().getWritableDatabaseWithRetry()!!
        val before = dataCanonical(db)
        // SQLiteOpenHelper가 잠금 밖에서 v18을 읽었지만, 잠금을 잡은 시점엔 이미 Flutter가 v24로 올린 상황
        db.beginTransaction()
        try {
            helper().onUpgrade(db, 18, 24)
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        assertEquals(before, dataCanonical(db))
        assertEquals(24, db.version)

        db.version = 25
        try {
            db.beginTransaction()
            try {
                helper().onUpgrade(db, 18, 24)
                fail("잠금 후 버전이 더 높으면 예외")
            } finally {
                db.endTransaction()
            }
        } catch (e: DbMigrationException) {
            // 기대
        }
    }

    @Test
    fun repairReject_oldFriendsStamped24_currentBehaviorRecorded() {
        installFixture("variant_v16_stamped24_oldfriends.db")
        val db = helper().getWritableDatabaseWithRetry()
        if (db == null) {
            println("REPAIR-REJECT 관찰(Native): open 실패(null)")
            return
        }
        val cols = G0TestSupport.query(db, "PRAGMA table_info(friends)").map { it["name"] }.toSet()
        val ids = G0TestSupport.query(db, "SELECT id FROM friends").map { it["id"] }
        println("REPAIR-REJECT 관찰(Native): open 성공, schema==reference ${schemaCanonical(db) == G0TestSupport.canonical(reference)}, friends 컬럼 $cols, 행 $ids")
        // 과거 DROP을 재실행해 정상처럼 숨기지 않았는지만 단정 (실패 전파 여부는 test_results.md에서 판정)
        assertEquals(listOf(701L), ids)
        assertFalse("owner_id" in cols)
    }

    @Test
    fun ruleCases_sharedWithDart() {
        val cases = JSONObject(G0TestSupport.readG0("runner_rule_cases.json")).getJSONArray("cases")
        val failures = ArrayList<String>()
        for (i in 0 until cases.length()) {
            val c = cases.getJSONObject(i)
            val json = G0TestSupport.applyMutation(JSONObject(G0TestSupport.repoScriptJson()), c.getJSONObject("mutation")).toString()
            val accepted = try {
                DbMigrationScript.parse(json); true
            } catch (e: DbMigrationException) {
                false
            }
            val want = c.getString("expect") == "accept"
            if (accepted != want) failures.add("${c.getString("name")}: expected ${c.getString("expect")}, accepted=$accepted")
        }
        assertEquals("rule case 개수", 20, cases.length())
        assertTrue(failures.joinToString("\n"), failures.isEmpty())
    }

    /** alarm_overrides 제약 동작 (Dart g0_constraint_checks.dart와 같은 케이스). 트랜잭션 롤백으로 행을 남기지 않음. */
    private fun expectOverridesConstraints(db: SQLiteDatabase) {
        fun row(vararg overrides: Pair<String, Any?>): ContentValues {
            val m = linkedMapOf<String, Any?>(
                "slot_time" to "2026-09-15T06:30:00", "shift_type" to "Day", "day_offset" to 0, "action" to "skip",
                "alarm_type_id" to null, "origin_date" to "2026-09-15", "origin_shift" to "Day", "created_at" to "2026-09-14T05:00:00"
            )
            overrides.forEach { m[it.first] = it.second }
            return ContentValues().apply {
                m.forEach { (k, v) ->
                    when (v) {
                        null -> putNull(k)
                        is Int -> put(k, v)
                        else -> put(k, v.toString())
                    }
                }
            }
        }
        fun rejected(vararg o: Pair<String, Any?>): Boolean = db.insert("alarm_overrides", null, row(*o)) == -1L

        db.beginTransaction()
        try {
            assertTrue(db.insert("alarm_overrides", null, row()) > 0)
            assertTrue(db.insert("alarm_overrides", null, row("slot_time" to "2026-09-15T07:00:00", "action" to "set_type", "alarm_type_id" to 2)) > 0)
            assertTrue(db.insert("alarm_overrides", null, row("day_offset" to -1)) > 0)
            assertTrue(db.insert("alarm_overrides", null, row("day_offset" to 1)) > 0)
            assertTrue("같은 슬롯 중복 거부", rejected())
            assertTrue("day_offset 범위", rejected("slot_time" to "2026-09-16T06:30:00", "day_offset" to 2))
            assertTrue("action 값", rejected("slot_time" to "2026-09-16T06:30:00", "action" to "delete"))
            assertTrue("skip + alarm_type_id", rejected("slot_time" to "2026-09-16T06:30:00", "alarm_type_id" to 1))
            assertTrue("set_type + null", rejected("slot_time" to "2026-09-16T06:30:00", "action" to "set_type"))
            assertTrue("origin_shift NOT NULL", rejected("slot_time" to "2026-09-16T06:30:00", "origin_shift" to null))
            assertFalse("근무명이 다르면 다른 슬롯", rejected("shift_type" to "Night"))
        } finally {
            db.endTransaction() // setTransactionSuccessful 없음 → 롤백
        }
        assertEquals(0L, G0TestSupport.query(db, "SELECT COUNT(*) AS n FROM alarm_overrides").first()["n"])
    }
}
