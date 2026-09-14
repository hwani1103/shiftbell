#!/usr/bin/env python3
"""G0(T03) DB 마이그레이션 테스트 fixture 빌더.

출시전_수정작업 실행계획 §11 T03. 입력은 T01(Codex)이 역사 Git에서 만든 SQL/manifest/expected.md.
이 스크립트는 G0 구현(assets/db/migrations.json, DbMigrationRunner)을 절대 읽지 않는다 -
기대값이 구현을 복사하는 자기검증이 되지 않게 하기 위함.

하는 일
  1. (--import-from) T01 원본을 test/release_audit/g0/fixtures_src/로 복사 (SQL은 LF로 정규화)
  2. SQL SHA256(LF 기준)이 manifest와 같은지 확인
  3. 각 SQL을 빈 SQLite 파일에 실행해 fixtures_db/vNN.db 생성 + user_version/입력 행 수/무결성 확인
  4. 손상·경계 변형 DB 생성 (variants)
  5. expected.md의 규칙 + manifest input_rows로 "v24 업그레이드 후 기대 데이터"를 expected_v24/*.json으로 계산

사용
  python tool/g0/build_fixtures.py --import-from <T01 fixtures_draft 폴더>   # 최초 1회
  python tool/g0/build_fixtures.py                                        # 재빌드
"""
import argparse
import hashlib
import json
import shutil
import sqlite3
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BASE = REPO / "test" / "release_audit" / "g0"
SRC = BASE / "fixtures_src"
DB_OUT = BASE / "fixtures_db"
EXP_OUT = BASE / "expected_v24"

# v24 최종 테이블과 컬럼 (Dart _onCreate 기준 목록). 기대 데이터의 "행이 가져야 할 컬럼 집합"에만 씀.
FINAL_COLUMNS = {
    "alarm_types": ["id", "name", "emoji", "sound_file", "volume", "vibration_strength", "is_preset", "duration"],
    "shift_schedule": ["id", "is_regular", "pattern", "today_index", "shift_types", "active_shift_types",
                       "start_date", "shift_colors", "custom_shift_colors", "assigned_dates", "shift_durations"],
    "alarms": ["id", "time", "date", "type", "alarm_type_id", "shift_type", "day_offset"],
    "shift_alarm_templates": ["id", "shift_type", "time", "alarm_type_id", "day_offset"],
    "alarm_history": ["id", "alarm_id", "scheduled_time", "scheduled_date", "actual_ring_time", "dismiss_type",
                      "snooze_count", "shift_type", "created_at", "day_offset"],
    "alarm_overrides": ["id", "slot_time", "shift_type", "day_offset", "action", "alarm_type_id", "origin_date",
                        "origin_shift", "created_at"],
    "date_memos": ["id", "date", "memo_text", "order_index", "created_at"],
    "date_schedules": ["id", "date", "content", "start_minutes", "duration_minutes", "color_index", "icon_index",
                       "style_index", "font_index", "predicted_category", "is_user_corrected", "notify_enabled",
                       "notify_offset_minutes", "created_at", "updated_at"],
    "alarm_creation_log": ["id", "alarm_id", "scheduled_date", "scheduled_time", "shift_type", "alarm_type_id",
                           "source", "created_at", "day_offset"],
    "date_overtime": ["id", "date", "minutes", "updated_at"],
    "friends": ["id", "name", "owner_id", "data_json", "added_at", "updated_at"],
    "condition_shift_times": ["shift_name", "start_minutes", "end_minutes", "updated_at"],
    "sleep_records": ["id", "start_time", "end_time", "source", "status", "confidence", "created_at", "updated_at"],
    "sleep_expected_bedtime": ["shift_key", "bedtime_minutes", "updated_at"],
}

# expected.md "데이터 기대값": 나중 버전에서 추가된 컬럼과 기존 행이 받는 값.
ADDED_COLUMN_DEFAULTS = {
    "shift_schedule": {"shift_colors": None, "assigned_dates": None, "active_shift_types": None,
                       "shift_durations": None, "custom_shift_colors": None},
    "alarm_types": {"duration": 10, "vibration_strength": 2},
    "alarms": {"day_offset": 0},
    "shift_alarm_templates": {"day_offset": 0},
    "alarm_history": {"day_offset": 0},
    "alarm_creation_log": {"day_offset": 0},
    "date_schedules": {"notify_enabled": 0, "notify_offset_minutes": 0},
}


def sha256_lf(path: Path) -> str:
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def import_sources(src_dir: Path) -> None:
    SRC.mkdir(parents=True, exist_ok=True)
    for p in sorted(src_dir.iterdir()):
        if p.suffix in (".sql", ".json", ".md"):
            data = p.read_bytes().replace(b"\r\n", b"\n") if p.suffix == ".sql" else p.read_bytes()
            (SRC / p.name).write_bytes(data)
    print(f"imported {src_dir} -> {SRC}")


def build_db(sql_text: str, out: Path) -> sqlite3.Connection:
    if out.exists():
        out.unlink()
    con = sqlite3.connect(out)
    con.isolation_level = None
    con.executescript(sql_text)
    return con


def expected_for(fixture: dict) -> dict:
    """expected.md 규칙으로 v24 업그레이드 후 기대 데이터 계산."""
    start = fixture["user_version"]
    tables = {}
    for table, columns in FINAL_COLUMNS.items():
        rows = [dict(r) for r in fixture["input_rows"].get(table, [])]
        if table == "friends" and start <= 16:
            rows = []  # 1~15: v17 이후 빈 owner_id 테이블 / 16: v17 전환에서 옛 행 제거
        for row in rows:
            extra = set(row) - set(columns)
            if extra:
                raise SystemExit(f"{fixture['file']} {table}: 최종 스키마에 없는 입력 컬럼 {extra}")
            for col in columns:
                if col not in row:
                    defaults = ADDED_COLUMN_DEFAULTS.get(table, {})
                    if col not in defaults:
                        raise SystemExit(f"{fixture['file']} {table}.{col}: 입력에 없고 추가 컬럼 규칙도 없음")
                    row[col] = defaults[col]
            if table == "alarm_types":
                rid = row["id"]
                if start <= 9 and rid == 1:
                    row.update(sound_file="alarmbell1", volume=0.7, vibration_strength=3, duration=3)
                if start <= 10 and rid == 2:
                    row.update(vibration_strength=3, duration=3)
                if start <= 10 and rid == 3:
                    row.update(duration=3)
        rows.sort(key=lambda r: json.dumps(r, sort_keys=True, ensure_ascii=False))
        tables[table] = rows
    return {"fixture": fixture["file"], "start_version": start, "user_version": 24, "tables": tables}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--import-from", type=Path)
    args = ap.parse_args()
    if args.import_from:
        import_sources(args.import_from)

    manifest = json.loads((SRC / "manifest.json").read_text(encoding="utf-8"))
    DB_OUT.mkdir(parents=True, exist_ok=True)
    EXP_OUT.mkdir(parents=True, exist_ok=True)
    failures = []
    index = {"fixtures": [], "variants": []}

    for fx in manifest["fixtures"]:
        sql_path = SRC / fx["file"]
        if sha256_lf(sql_path) != fx["sha256"]:
            failures.append(f"{fx['file']}: SHA256 불일치")
            continue
        db_path = DB_OUT / (Path(fx["file"]).stem + ".db")
        con = build_db(sql_path.read_text(encoding="utf-8"), db_path)
        uv = con.execute("PRAGMA user_version").fetchone()[0]
        if uv != fx["user_version"]:
            failures.append(f"{fx['file']}: user_version {uv} != {fx['user_version']}")
        for t, rows in fx["input_rows"].items():
            n = con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
            if n != len(rows):
                failures.append(f"{fx['file']}: {t} 행 수 {n} != {len(rows)}")
        if con.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            failures.append(f"{fx['file']}: integrity_check 실패")
        con.close()
        exp = expected_for(fx)
        (EXP_OUT / (Path(fx["file"]).stem + ".json")).write_text(
            json.dumps(exp, ensure_ascii=False, indent=1, sort_keys=True), encoding="utf-8")
        index["fixtures"].append({"db": db_path.name, "expected": Path(fx["file"]).stem + ".json",
                                  "start_version": fx["user_version"]})

    by_file = {fx["file"]: fx for fx in manifest["fixtures"]}
    v23_sql = (SRC / "v23.sql").read_text(encoding="utf-8")

    # MISSING-COLUMN: 정상 v23에서 컬럼/인덱스를 빼고 버전만 24로 선행 (과거 ALTER 실패를 삼키던 시절의 손상 형태)
    p = DB_OUT / "variant_v23_stamped24_missing.db"
    con = build_db(v23_sql, p)
    con.executescript("ALTER TABLE date_schedules DROP COLUMN notify_offset_minutes;"
                      "DROP INDEX IF EXISTS idx_sleep_records_start;"
                      "PRAGMA user_version = 24;")
    con.close()
    exp = expected_for(by_file["v23.sql"])
    for row in exp["tables"]["date_schedules"]:
        row["notify_offset_minutes"] = 0  # 값이 사라진 컬럼은 repair가 DEFAULT 0으로 다시 만듦
    exp["fixture"] = p.name
    (EXP_OUT / "variant_v23_stamped24_missing.json").write_text(
        json.dumps(exp, ensure_ascii=False, indent=1, sort_keys=True), encoding="utf-8")
    index["variants"].append({"db": p.name, "expected": "variant_v23_stamped24_missing.json",
                              "case": "MISSING-COLUMN"})

    # FUTURE-VERSION: 더 높은 버전
    p = DB_OUT / "variant_v23_stamped25.db"
    con = build_db(v23_sql, p)
    con.execute("PRAGMA user_version = 25")
    con.close()
    index["variants"].append({"db": p.name, "case": "FUTURE-VERSION"})

    # NATIVE-NEW 경계: 파일은 있는데 테이블 0개, user_version 0
    p = DB_OUT / "variant_empty_v0.db"
    con = build_db("CREATE TABLE t(x); DROP TABLE t;", p)
    con.close()
    index["variants"].append({"db": p.name, "case": "VERSION-ZERO"})

    # REPAIR-REJECT: v17 전환을 건너뛴 채 최신 버전으로 찍힌 DB (옛 friends 형태 - repair 허용 범위 밖)
    p = DB_OUT / "variant_v16_stamped24_oldfriends.db"
    con = build_db((SRC / "v16.sql").read_text(encoding="utf-8"), p)
    con.execute("PRAGMA user_version = 24")
    con.close()
    index["variants"].append({"db": p.name, "case": "REPAIR-REJECT"})

    # AlarmRefreshEngineH2Test 전용 최소 스키마(그 테스트가 원래 쓰던 컬럼 그대로) + user_version 24.
    # G0 이후 Native onCreate가 예외라 "빈 파일을 헬퍼로 먼저 연다"는 기존 준비 방식을 못 쓰고,
    # 그 테스트 주석대로 Robolectric에서 원시 연결로 파일을 만들면 연결 오류가 나서 여기서 미리 만든다.
    p = DB_OUT / "aux_h2_minimal_v24.db"
    con = build_db(
        "CREATE TABLE shift_schedule (id INTEGER PRIMARY KEY AUTOINCREMENT, is_regular INTEGER, pattern TEXT, "
        "today_index INTEGER, start_date TEXT, assigned_dates TEXT);"
        "CREATE TABLE shift_alarm_templates (id INTEGER PRIMARY KEY AUTOINCREMENT, shift_type TEXT, time TEXT, "
        "alarm_type_id INTEGER, day_offset INTEGER);"
        "CREATE TABLE alarms (id INTEGER PRIMARY KEY AUTOINCREMENT, time TEXT, date TEXT, type TEXT, "
        "alarm_type_id INTEGER, shift_type TEXT, day_offset INTEGER);"
        "CREATE TABLE alarm_history (id INTEGER PRIMARY KEY AUTOINCREMENT, alarm_id INTEGER, scheduled_time TEXT, "
        "scheduled_date TEXT, actual_ring_time TEXT, dismiss_type TEXT, snooze_count INTEGER, shift_type TEXT, "
        "created_at TEXT, day_offset INTEGER);"
        "CREATE TABLE alarm_creation_log (id INTEGER PRIMARY KEY AUTOINCREMENT, alarm_id INTEGER, scheduled_date TEXT, "
        "scheduled_time TEXT, shift_type TEXT, alarm_type_id INTEGER, source TEXT, created_at TEXT, day_offset INTEGER);"
        "PRAGMA user_version = 24;", p)
    con.close()
    index["variants"].append({"db": p.name, "case": "H2-TEST-FIXTURE"})

    (BASE / "fixtures_index.json").write_text(json.dumps(index, ensure_ascii=False, indent=1), encoding="utf-8")

    if failures:
        print("FAILURES:\n  " + "\n  ".join(failures))
        return 1
    print(f"OK: {len(index['fixtures'])} fixtures, {len(index['variants'])} variants -> {DB_OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
