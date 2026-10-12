"""One-shot dev-phone time-zone probe. Restores the phone zone and removes its fixture."""
import json
import re
import time

from usb_audit_device import OUT, SERIAL, adb, connect_vm, evaluate

assert SERIAL == "R5KL20DHWAE", "This probe is restricted to the connected dev phone"


def setting(name):
    return adb("shell", "settings", "get", "global", name).decode().strip()


def zone():
    return adb("shell", "getprop", "persist.sys.timezone").decode().strip()


def is_reserved(epoch, evidence_name):
    dump = adb("shell", "dumpsys", "alarm").decode("utf-8", errors="replace")
    (OUT / f"{evidence_name}_alarmmanager.txt").write_text(dump, encoding="utf-8")
    pattern = (
        rf"RTC_WAKEUP #\d+: Alarm\{{[^\n]+origWhen {epoch}[^\n]+ "
        r"com\.hwani1103\.shiftbell\.dev\}\r?\n\s+tag=[^\n]*CustomAlarmReceiver"
    )
    return re.search(pattern, dump) is not None


original_zone = zone()
original_auto_zone = setting("auto_time_zone")
assert original_zone == "Asia/Seoul", f"Unexpected starting zone: {original_zone}"
assert (OUT / "phone_before_de.tar").exists(), "Back up device data first"

fixture_id = None
fixture_epoch = None
result = {"starting_zone": original_zone, "starting_auto_time_zone": original_auto_zone}
try:
    connect_vm()
    fixture = evaluate(
        "tz_fixture_create",
        "services/database_service.dart",
        """(() async {
          final now = DateTime.now();
          final at = DateTime(now.year, now.month, now.day, now.hour + 2, now.minute + 1);
          final time = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
          final db = await DatabaseService.instance.database;
          final id = await db.insert('alarms', {
            'time': time, 'date': at.toIso8601String(), 'type': 'fixed',
            'alarm_type_id': 1, 'shift_type': '__timezone_probe__', 'day_offset': 0,
          });
          await kAlarmChannel.invokeMethod('scheduleNativeAlarm', {
            'id': id, 'timestamp': at.millisecondsSinceEpoch, 'label': '__timezone_probe__'
          });
          return '$id|${at.millisecondsSinceEpoch}';
        })()""".replace("\n", " "),
    )
    fixture_id, fixture_epoch = map(int, fixture.split("|"))
    result["fixture_id"] = fixture_id
    result["fixture_epoch"] = fixture_epoch
    result["reserved_before"] = is_reserved(fixture_epoch, "tz_before")
    assert result["reserved_before"], "Fixture OS reservation was not visible"

    adb("shell", "settings", "put", "global", "auto_time_zone", "0")
    adb("shell", "cmd", "alarm", "set-timezone", "Pacific/Kiritimati")
    assert zone() == "Pacific/Kiritimati", "Time-zone change did not take effect"
    result["changed_zone"] = zone()
    for _ in range(12):
        if not is_reserved(fixture_epoch, "tz_after_broadcast"):
            break
        time.sleep(1)
    result["reserved_after_broadcast"] = is_reserved(fixture_epoch, "tz_after_broadcast")

    # Also cover the app-initiated refresh if the system broadcast was delayed.
    evaluate(
        "tz_force_refresh",
        "services/database_service.dart",
        "(() async {return '${await kAlarmChannel.invokeMethod<bool>('forceNativeRefreshAndWait')}';})()",
    )
    result["reserved_after_force_refresh"] = is_reserved(fixture_epoch, "tz_after_force_refresh")
    state = evaluate(
        "tz_db_state",
        "services/database_service.dart",
        f"""(() async {{
          final db = await DatabaseService.instance.database;
          final rows = await db.query('alarms', where: 'id=?', whereArgs: [{fixture_id}]);
          return '${{rows.length}}|${{rows.isEmpty ? false : Alarm.fromMap(rows.single).date!.isBefore(DateTime.now())}}';
        }})()""".replace("\n", " "),
    )
    result["past_row_kept"] = state == "1|true"
    assert result["past_row_kept"] and not result["reserved_after_force_refresh"]
finally:
    if fixture_id is not None:
        try:
            evaluate(
                "tz_fixture_cleanup",
                "services/database_service.dart",
                f"""(() async {{
                  final db = await DatabaseService.instance.database;
                  await db.delete('alarms', where: 'id=?', whereArgs: [{fixture_id}]);
                  await kAlarmChannel.invokeMethod('cancelNativeAlarm', {{'id': {fixture_id}}});
                  return 'cleaned';
                }})()""".replace("\n", " "),
            )
            result["fixture_cleaned"] = True
        except Exception as exc:
            result["fixture_cleanup_error"] = type(exc).__name__
    adb("shell", "cmd", "alarm", "set-timezone", original_zone)
    adb("shell", "settings", "put", "global", "auto_time_zone", original_auto_zone)
    result["restored_zone"] = zone()
    result["restored_auto_time_zone"] = setting("auto_time_zone")
    try:
        evaluate(
            "tz_restore_refresh",
            "services/database_service.dart",
            "(() async {return '${await kAlarmChannel.invokeMethod<bool>('forceNativeRefreshAndWait')}';})()",
        )
    except Exception as exc:
        result["restore_refresh_error"] = type(exc).__name__
    (OUT / "tz_probe_result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
