// android/app/src/main/kotlin/com/hwani1103/shiftbell/DbMigrationRunner.kt
//
// ⭐ 2026-09-14 (G0) - DB 스키마 SQL 단일 원본(assets/db/migrations.json) 실행기의 Native 쪽.
// 출시전_코드감사_검토결과_v4 #1/#8/#31 참고. DatabaseHelper.onUpgrade/onOpen이 호출함.
//
// ⚠️ Dart 쌍: lib/services/db_migration_runner.dart
// 파싱 규칙·실행 규칙(한 항목 = SQL 한 문장, ALTER ADD COLUMN 존재 확인, repair 화이트리스트,
// repair의 CREATE TABLE 선행)을 두 언어가 똑같이 유지해야 함. 바꾸면 같은 커밋에서 양쪽을
// 바꾸고 같은 fixture로 비교할 것.
package com.hwani1103.shiftbell

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

class DbMigrationException(message: String) : IllegalStateException(message)

class DbMigrationScript private constructor(
    val targetVersion: Int,
    /** 버전 → 그 버전으로 올릴 때 실행할 SQL(순서대로). 2..targetVersion 전 구간이 반드시 있음. */
    val migrations: Map<Int, List<String>>,
    /** 현재 스키마의 최종 형태 중 비파괴 SQL만 (CREATE TABLE이 항상 먼저). */
    val repair: List<String>
) {
    companion object {
        // Flutter 자산(pubspec.yaml assets)은 APK 안에서 flutter_assets/ 아래에 들어감.
        // release·잠금 해제 전에도 읽히는지는 실기기 S1에서 확인해야 함.
        const val ASSET_PATH = "flutter_assets/assets/db/migrations.json"

        @Volatile
        private var cached: DbMigrationScript? = null

        // 테스트 전용 - Robolectric 단위 테스트에는 flutter_assets가 합쳐지지 않으므로
        // 저장소의 assets/db/migrations.json을 직접 parse()해서 주입함.
        @Volatile
        internal var overrideForTest: DbMigrationScript? = null

        fun load(context: Context): DbMigrationScript {
            overrideForTest?.let { return it }
            cached?.let { return it }
            val text = context.assets.open(ASSET_PATH).bufferedReader(Charsets.UTF_8).use { it.readText() }
            return parse(text).also { cached = it }
        }

        fun parse(jsonText: String): DbMigrationScript {
            val root = try {
                JSONObject(jsonText)
            } catch (e: JSONException) {
                throw DbMigrationException("JSON 파싱 실패: ${e.message}")
            }
            val format = root.opt("format")
            if (format != 1) throw DbMigrationException("지원하지 않는 format: $format")
            val target = root.opt("targetVersion")
            if (target !is Int || target < 2) {
                throw DbMigrationException("targetVersion이 2 이상의 정수가 아님: $target")
            }

            val rawMigrations = root.opt("migrations") as? JSONArray
                ?: throw DbMigrationException("migrations가 배열이 아님")
            val migrations = HashMap<Int, List<String>>()
            for (i in 0 until rawMigrations.length()) {
                val entry = rawMigrations.opt(i) as? JSONObject
                    ?: throw DbMigrationException("migrations[$i]가 객체가 아님")
                val version = entry.opt("version")
                if (version !is Int || version < 2 || version > target) {
                    throw DbMigrationException("migrations 항목 version이 2..$target 범위 정수가 아님: $version")
                }
                if (migrations.containsKey(version)) {
                    throw DbMigrationException("migrations에 v${version}이 중복됨")
                }
                val sql = entry.opt("sql") as? JSONArray
                if (sql == null || sql.length() == 0) {
                    throw DbMigrationException("v${version}의 sql이 비어 있음")
                }
                migrations[version] = (0 until sql.length()).map { singleStatement(sql.opt(it), "v$version") }
            }
            for (v in 2..target) {
                if (!migrations.containsKey(v)) {
                    throw DbMigrationException("migrations에 v${v}가 없음 (v2..v$target 전 구간이 필요)")
                }
            }

            val rawRepair = root.opt("repair") as? JSONArray
                ?: throw DbMigrationException("repair가 배열이 아님")
            val repair = (0 until rawRepair.length()).map { singleStatement(rawRepair.opt(it), "repair") }
            DbMigrationRunner.validateRepair(repair)

            return DbMigrationScript(target, migrations.toMap(), repair)
        }

        private fun singleStatement(value: Any?, where: String): String {
            if (value !is String) throw DbMigrationException("$where: SQL이 문자열이 아님: $value")
            val sql = value.trim()
            if (sql.isEmpty()) throw DbMigrationException("$where: 빈 SQL")
            // execSQL은 여러 문장 중 첫 문장만 실행하고 나머지를 조용히 버림 - 한 항목에 한 문장만.
            if (sql.contains(';')) throw DbMigrationException("$where: 한 항목에 SQL 한 문장만 허용(; 금지): $sql")
            return sql
        }
    }
}

object DbMigrationRunner {
    private const val TAG = "DbMigrationRunner"

    private val ALTER_ADD_COLUMN = Regex("""^ALTER\s+TABLE\s+(\w+)\s+ADD\s+COLUMN\s+(\w+)\b""", RegexOption.IGNORE_CASE)
    private val CREATE_TABLE = Regex("""^CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+(\w+)\s*\(""", RegexOption.IGNORE_CASE)
    private val CREATE_INDEX = Regex("""^CREATE\s+(?:UNIQUE\s+)?INDEX\s+IF\s+NOT\s+EXISTS\s+(\w+)\s+ON\s+(\w+)\s*\(""", RegexOption.IGNORE_CASE)

    /**
     * [fromVersion] 다음 버전부터 [toVersion]까지 전부 순서대로 실행. 실패는 그대로 던짐 -
     * SQLiteOpenHelper가 onUpgrade와 버전 갱신을 한 트랜잭션으로 묶으므로 함께 롤백되고,
     * 다음 DB 접근 때 같은 구간을 다시 시도하게 됨.
     */
    fun migrate(db: SQLiteDatabase, script: DbMigrationScript, fromVersion: Int, toVersion: Int) {
        if (toVersion != script.targetVersion) {
            throw DbMigrationException("목표 버전(v$toVersion)이 SQL 원본 targetVersion(v${script.targetVersion})과 다름")
        }
        if (fromVersion < 1 || fromVersion >= toVersion) {
            throw DbMigrationException("지원하지 않는 업그레이드 구간: v$fromVersion → v$toVersion")
        }
        for (v in (fromVersion + 1)..toVersion) {
            for (sql in script.migrations.getValue(v)) {
                val alter = ALTER_ADD_COLUMN.find(sql)
                if (alter != null && columnExists(db, alter.groupValues[1], alter.groupValues[2])) continue
                db.execSQL(sql)
            }
            Log.i(TAG, "✅ DB 업그레이드 v${v - 1} → v$v")
        }
    }

    /** 지금 DB에 없는 repair 항목만 (읽기만 함). */
    fun pendingRepairs(db: SQLiteDatabase, script: DbMigrationScript): List<String> {
        val pending = ArrayList<String>()
        for (sql in script.repair) {
            val table = CREATE_TABLE.find(sql)
            if (table != null) {
                if (!schemaObjectExists(db, "table", table.groupValues[1])) pending.add(sql)
                continue
            }
            val index = CREATE_INDEX.find(sql)
            if (index != null) {
                if (!schemaObjectExists(db, "index", index.groupValues[1])) pending.add(sql)
                continue
            }
            val alter = ALTER_ADD_COLUMN.find(sql)
            if (alter != null) {
                val tableName = alter.groupValues[1]
                // 테이블 자체가 없으면 앞의 CREATE TABLE(최종 형태)이 이 컬럼까지 만들어 줌.
                if (schemaObjectExists(db, "table", tableName) && !columnExists(db, tableName, alter.groupValues[2])) {
                    pending.add(sql)
                }
                continue
            }
            throw DbMigrationException("repair에 허용되지 않은 SQL: $sql")
        }
        return pending
    }

    /**
     * 버전은 최신인데 테이블/컬럼/인덱스가 빠진 DB를 비파괴로 채움. 과거 마이그레이션은
     * 절대 다시 실행하지 않음(v17 DROP TABLE friends, v8~v11 UPDATE 재실행 방지).
     */
    fun repair(db: SQLiteDatabase, script: DbMigrationScript) {
        if (pendingRepairs(db, script).isEmpty()) return
        db.beginTransaction()
        try {
            // 쓰기 잠금을 잡은 뒤 다시 계산 - 그사이 Flutter가 먼저 채웠을 수 있음.
            val pending = pendingRepairs(db, script)
            for (sql in pending) db.execSQL(sql)
            db.setTransactionSuccessful()
            Log.w(TAG, "🛠️ DB 스키마 복구 ${pending.size}건 실행")
        } finally {
            db.endTransaction()
        }
    }

    internal fun validateRepair(repair: List<String>) {
        val createdTables = HashSet<String>()
        var seenNonCreateTable = false
        for (sql in repair) {
            val table = CREATE_TABLE.find(sql)
            if (table != null) {
                if (seenNonCreateTable) {
                    throw DbMigrationException("repair: CREATE TABLE은 인덱스/ALTER보다 앞에 있어야 함: $sql")
                }
                createdTables.add(table.groupValues[1].lowercase())
                continue
            }
            val targetTable = ALTER_ADD_COLUMN.find(sql)?.groupValues?.get(1)
                ?: CREATE_INDEX.find(sql)?.groupValues?.get(2)
                ?: throw DbMigrationException(
                    "repair에 허용되지 않은 SQL(CREATE TABLE/INDEX IF NOT EXISTS, ALTER TABLE ADD COLUMN만 허용): $sql"
                )
            seenNonCreateTable = true
            if (targetTable.lowercase() !in createdTables) {
                throw DbMigrationException("repair: 대상 테이블($targetTable)의 최종 형태 CREATE TABLE이 repair에 없음: $sql")
            }
        }
    }

    private fun schemaObjectExists(db: SQLiteDatabase, type: String, name: String): Boolean {
        db.rawQuery(
            "SELECT 1 FROM sqlite_master WHERE type = ? AND lower(name) = lower(?)",
            arrayOf(type, name)
        ).use { return it.moveToFirst() }
    }

    private fun columnExists(db: SQLiteDatabase, table: String, column: String): Boolean {
        // table은 정규식 \w+로만 뽑힌 이름이라 그대로 넣어도 안전.
        db.rawQuery("PRAGMA table_info($table)", null).use { cursor ->
            val nameIndex = cursor.getColumnIndexOrThrow("name")
            while (cursor.moveToNext()) {
                if (cursor.getString(nameIndex).equals(column, ignoreCase = true)) return true
            }
        }
        return false
    }
}
