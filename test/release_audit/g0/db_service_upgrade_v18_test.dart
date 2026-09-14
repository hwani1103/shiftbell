// test/release_audit/g0/db_service_upgrade_v18_test.dart
//
// G0(T03) - 복제한 옵션이 아닌 실제 DatabaseService 경로로 운영 버전(v1.0.22, DB v18) fixture를 v24로 올린다.
// DatabaseService는 프로세스 전역 싱글턴이라 fixture 하나당 테스트 파일 하나를 쓴다(v12는 별도 파일).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'g0_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initFfi);

  test('DatabaseService가 v18 fixture를 v24로 올림 - 기대 데이터·기준 구조 일치', () async {
    final dir = await Directory.systemTemp.createTemp('g0_service_v18_');
    await databaseFactory.setDatabasesPath(dir.path);
    await copyFixture('v18.db', dir, asName: 'shiftbell.db');

    final db = await DatabaseService.instance.database;
    expect(await db.getVersion(), 24);
    expect(diffExpectedData(await dumpTables(db), readJson('expected_v24/v18.json')), isEmpty);
    expect(canonicalJson(await schemaSnapshot(db)), canonicalJson(readJson('v24_oncreate_schema.json')));
  });
}
