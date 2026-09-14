// android/app/src/test/kotlin/com/hwani1103/shiftbell/G0TestSupport.kt
//
// G0(T03) Native DB 테스트 공통 도구. Dart 쪽 쌍: test/release_audit/g0/g0_support.dart (같은 정규화 규칙).
// fixture/기대값/기준 스키마는 저장소의 test/release_audit/g0/ 아래 파일을 그대로 읽는다
// (tool/g0/build_fixtures.py가 T01 원본으로 만든 것 + Dart _onCreate로 만든 v24_oncreate_schema.json).
package com.hwani1103.shiftbell

import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

object G0TestSupport {
    val repoRoot: File by lazy {
        var dir: File? = File(System.getProperty("user.dir")!!).absoluteFile
        while (dir != null && !File(dir, "assets/db/migrations.json").exists()) dir = dir.parentFile
        dir ?: error("저장소 루트(assets/db/migrations.json)를 찾지 못함: user.dir=${System.getProperty("user.dir")}")
    }

    val g0Dir: File get() = File(repoRoot, "test/release_audit/g0")

    fun readG0(relative: String): String = File(g0Dir, relative).readText(Charsets.UTF_8)

    fun repoScriptJson(): String = File(repoRoot, "assets/db/migrations.json").readText(Charsets.UTF_8)

    fun fixtureIndex(): List<JSONObject> {
        val arr = JSONObject(readG0("fixtures_index.json")).getJSONArray("fixtures")
        return (0 until arr.length()).map { arr.getJSONObject(it) }
    }

    private val EXCLUDED_TABLES = setOf("android_metadata")

    private fun cellValue(c: Cursor, i: Int): Any? = when (c.getType(i)) {
        Cursor.FIELD_TYPE_NULL -> null
        Cursor.FIELD_TYPE_INTEGER -> c.getLong(i)
        Cursor.FIELD_TYPE_FLOAT -> c.getDouble(i)
        Cursor.FIELD_TYPE_STRING -> c.getString(i)
        else -> "blob:" + c.getBlob(i).joinToString("") { "%02x".format(it) }
    }

    fun query(db: SQLiteDatabase, sql: String): List<Map<String, Any?>> =
        db.rawQuery(sql, null).use { c ->
            val rows = ArrayList<Map<String, Any?>>()
            while (c.moveToNext()) {
                val row = LinkedHashMap<String, Any?>()
                for (i in 0 until c.columnCount) row[c.getColumnName(i)] = cellValue(c, i)
                rows.add(row)
            }
            rows
        }

    private fun tableNames(db: SQLiteDatabase): List<String> =
        query(db, "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
            .map { it["name"] as String }
            .filter { it !in EXCLUDED_TABLES }

    /** Dart schemaSnapshot과 같은 구조. */
    fun schemaSnapshot(db: SQLiteDatabase): Map<String, Any?> {
        val result = LinkedHashMap<String, Any?>()
        for (name in tableNames(db)) {
            val columns = query(db, "PRAGMA table_info($name)").map {
                mapOf(
                    "name" to it["name"],
                    "type" to (it["type"] as String).uppercase(),
                    "notnull" to it["notnull"],
                    "dflt" to it["dflt_value"],
                    "pk" to it["pk"],
                )
            }.sortedBy { it["name"] as String }
            val pkColumns = columns.filter { (it["pk"] as Long) > 0 }.sortedBy { it["pk"] as Long }.map { it["name"] }
            val indexes = query(db, "PRAGMA index_list($name)").map { idx ->
                val indexName = idx["name"] as String
                val cols = query(db, "PRAGMA index_info(\"$indexName\")")
                    .sortedBy { (it["seqno"] as Long) }
                    .map { it["name"] }
                // Robolectric의 SQLite는 index_list에 origin/partial 열이 없어 null로 옴(Dart ffi SQLite엔 있음).
                // 비교 강도를 유지하려고 같은 의미를 sqlite_master에서 직접 계산한다.
                val sql = query(db, "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = '$indexName'")
                    .firstOrNull()?.get("sql") as String?
                val origin = idx["origin"] ?: when {
                    !indexName.startsWith("sqlite_autoindex_") -> "c"
                    cols == pkColumns -> "pk"
                    else -> "u"
                }
                val partial = idx["partial"] ?: if (sql != null && Regex("""\bWHERE\b""", RegexOption.IGNORE_CASE).containsMatchIn(sql)) 1L else 0L
                mapOf("unique" to idx["unique"], "origin" to origin, "partial" to partial, "columns" to cols)
            }.sortedBy { canonical(it) }
            val fks = query(db, "PRAGMA foreign_key_list($name)").map {
                mapOf("table" to it["table"], "from" to it["from"], "to" to it["to"])
            }.sortedBy { canonical(it) }
            result[name] = mapOf("columns" to columns, "indexes" to indexes, "foreign_keys" to fks)
        }
        return result
    }

    fun dumpTables(db: SQLiteDatabase): Map<String, List<Map<String, Any?>>> =
        tableNames(db).associateWith { name -> query(db, "SELECT * FROM $name").sortedBy { canonical(it) } }

    /** 키 정렬 + 숫자 정규화(정수값 실수는 정수 표기). Dart canonicalJson과 같은 규칙. */
    fun canonical(value: Any?): String = when {
        value == null || value == JSONObject.NULL -> "null"
        value is Boolean -> value.toString()
        value is Double || value is Float -> {
            val d = (value as Number).toDouble()
            if (!d.isInfinite() && d == Math.floor(d)) d.toLong().toString() else d.toString()
        }
        value is Number -> value.toLong().toString()
        value is String -> JSONObject.quote(value)
        value is JSONObject -> canonical(value.keys().asSequence().toList().associateWith { value.get(it) })
        value is JSONArray -> canonical((0 until value.length()).map { value.get(it) })
        value is Map<*, *> -> value.keys.map { it.toString() }.sorted()
            .joinToString(",", "{", "}") { k -> JSONObject.quote(k) + ":" + canonical(value[k]) }
        value is List<*> -> value.joinToString(",", "[", "]") { canonical(it) }
        else -> error("정규화할 수 없는 값: $value (${value.javaClass})")
    }

    /** 기대 데이터(expected_v24 폴더의 json)와의 테이블별 불일치 목록. 비어 있으면 일치. */
    fun diffExpectedData(actual: Map<String, List<Map<String, Any?>>>, expected: JSONObject): List<String> {
        val problems = ArrayList<String>()
        val tables = expected.getJSONObject("tables")
        for (table in tables.keys()) {
            val arr = tables.getJSONArray(table)
            val exp = (0 until arr.length()).map { canonical(arr.get(it)) }.sorted()
            val act = (actual[table] ?: emptyList()).map { canonical(it) }.sorted()
            if (exp != act) problems.add("$table\n  expected: ${exp.joinToString(" | ")}\n  actual:   ${act.joinToString(" | ")}")
        }
        for (table in actual.keys) {
            if (!tables.has(table) && table != "sqlite_sequence") problems.add("기대 데이터에 없는 테이블: $table")
        }
        return problems
    }

    /** runner_rule_cases.json 변형 연산. Dart applyMutation과 같은 의미. */
    fun applyMutation(script: JSONObject, mutation: JSONObject): JSONObject {
        val copy = JSONObject(script.toString())
        val repair = copy.getJSONArray("repair")
        val migrations = copy.getJSONArray("migrations")
        fun entry(version: Int): JSONObject =
            (0 until migrations.length()).map { migrations.getJSONObject(it) }.first { it.getInt("version") == version }
        for (op in mutation.keys()) {
            when (op) {
                "repair_append" -> repair.put(mutation.getString(op))
                "migration_append" -> {
                    val m = mutation.getJSONObject(op)
                    entry(m.getInt("version")).getJSONArray("sql").put(m.getString("sql"))
                }
                "migration_insert_after" -> {
                    val m = mutation.getJSONObject(op)
                    val sql = entry(m.getInt("version")).getJSONArray("sql")
                    val list = (0 until sql.length()).map { sql.getString(it) }.toMutableList()
                    list.add(m.getInt("index") + 1, m.getString("sql"))
                    entry(m.getInt("version")).put("sql", JSONArray(list))
                }
                "remove_migration_version" -> {
                    val v = mutation.getInt(op)
                    val kept = (0 until migrations.length()).map { migrations.getJSONObject(it) }.filter { it.getInt("version") != v }
                    copy.put("migrations", JSONArray(kept))
                }
                "duplicate_migration_version" -> migrations.put(JSONObject(entry(mutation.getInt(op)).toString()))
                "set_target_version" -> copy.put("targetVersion", mutation.getInt(op))
                "set_format" -> copy.put("format", mutation.getInt(op))
                "replace_repair" -> {
                    val m = mutation.getJSONObject(op)
                    val i = (0 until repair.length()).indexOfFirst { repair.getString(it) == m.getString("from") }
                    check(i >= 0) { "replace_repair 대상 없음: ${m.getString("from")}" }
                    repair.put(i, m.getString("to"))
                }
                else -> error("알 수 없는 변형: $op")
            }
        }
        return copy
    }
}
