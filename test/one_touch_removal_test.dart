import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/services/db_migration_runner.dart';
import 'package:shiftbell/services/backup_policy.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'release_audit/g0/g0_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initFfi);
  Future<String> prepare() async {
    final dir = await Directory.systemTemp.createTemp('remove_dev_onetouch_');
    addTearDown(() => dir.delete(recursive: true));
    final path = await copyFixture('aux_h2_minimal_v24.db',dir);
    final old = loadRepoScriptJson()..['targetVersion']=26;
    (old['migrations'] as List).removeWhere((m) => m['version'] > 26);
    final db = await openLikeProduct(path,DbMigrationScript.parse(jsonEncode(old)));
    await db.delete('alarms');
    for (final item in [(1,'fixed',null),(2,'custom',null),(3,'snoozed',null),(98,'custom',0),(99,'snoozed',1)]) {
      await db.insert('alarms',{'id':item.$1,'time':'07:00','date':'2030-01-01T07:00:00',
        'type':item.$2,'alarm_type_id':1,'shift_type':'Day','day_offset':0,
        'preset_slot':item.$3,'assigned_day':item.$3==null?null:'2030-01-01'});
    }
    await db.close();
    return path;
  }
  test('v26 removal preserves ordinary alarms, histories, IDs and drops dev-only columns', () async {
    final path = await prepare();
    var db = await openLikeProduct(path,loadRepoScript());
    expect((await db.query('alarms')).map((r)=>r['id']),[1,2,3]);
    final columns=(await db.rawQuery('PRAGMA table_info(alarms)')).map((r)=>r['name']);
    expect(columns, isNot(contains('preset_slot')));
    expect(columns, isNot(contains('assigned_day')));
    final history = await db.query('alarm_history',where:'alarm_id IN (98,99)');
    expect(history,hasLength(2));
    expect(history.every((r)=>r['dismiss_type']=='cancelled_before_ring'),isTrue);
    final next=await db.insert('alarms',{'time':'09:00','date':'2030-01-02T09:00:00','type':'fixed','alarm_type_id':1});
    expect(next,greaterThan(99),reason:'Old OS PendingIntent IDs must never collide with new alarms');
    await db.close();
    db=await openLikeProduct(path,loadRepoScript());
    expect(await db.query('alarm_history',where:'alarm_id IN (98,99)'),hasLength(2));
    await db.close();
  });
  test('failed removal rolls back schema, removed alarms and cancellation histories', () async {
    final path=await prepare();
    final broken=loadRepoScriptJson();
    ((broken['migrations'] as List).last['sql'] as List).add('CREATE TABLE alarms(x INTEGER)');
    await expectLater(openLikeProduct(path,DbMigrationScript.parse(jsonEncode(broken))),throwsA(anything));
    final db=await openDatabase(path,singleInstance:false);
    expect(await db.getVersion(),26);
    expect(await db.query('alarms'),hasLength(5));
    expect(await db.query('alarm_history',where:'alarm_id IN (98,99)'),isEmpty);
    await db.close();
  });
  test('removed development preferences cannot return through backup', () {
    expect(isBackupPreferenceKey('custom_alarm_presets'),isFalse);
    expect(isBackupPreferenceKey('one_touch_alarm_tutorial_shown'),isFalse);
    expect(isBackupPreferenceKey('default_snooze_minutes'),isTrue);
  });
}
