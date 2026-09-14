// test/release_audit/g0/db_service_upgrade_v12_test.dart
//
// G0(T03) - 실제 DatabaseService 경로로 가장 오래된 스토어 배포 DB 버전(v12, 1.0.1~1.0.11) fixture를 v24로 올린다.
// (v8~v11 UPDATE를 지나지 않는 구간, v17 friends 재설계를 지나는 구간)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'g0_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initFfi);

  test('DatabaseService가 v12 fixture를 v24로 올림 - 기대 데이터·기준 구조 일치', () async {
    final dir = await Directory.systemTemp.createTemp('g0_service_v12_');
    await databaseFactory.setDatabasesPath(dir.path);
    await copyFixture('v12.db', dir, asName: 'shiftbell.db');

    final db = await DatabaseService.instance.database;
    expect(await db.getVersion(), 24);
    expect(diffExpectedData(await dumpTables(db), readJson('expected_v24/v12.json')), isEmpty);
    expect(canonicalJson(await schemaSnapshot(db)), canonicalJson(readJson('v24_oncreate_schema.json')));
  });
}
