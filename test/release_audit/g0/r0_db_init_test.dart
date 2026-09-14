// test/release_audit/g0/r0_db_init_test.dart
//
// G0 R0 교차 리뷰 반영 확인 - R0-01(경로 조회 실패 시 다른 DB로 대체 금지), R0-04(첫 초기화 실패가
// 처리되지 않은 비동기 오류로 한 번 더 새지 않음, 다음 호출은 새로 시도).
// DatabaseService는 프로세스 전역 싱글턴이라 이 파일 하나에서 실패 → 성공 순서로 확인한다.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'g0_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initFfi);
  tearDown(() => DatabaseService.debugIsAndroidOverride = null);

  test('Android에서 DB 경로 조회 실패 → 예외 전파, 일반 경로 DB 미생성, 새는 오류 없음, 다음 호출은 새로 시도', () async {
    final dir = await Directory.systemTemp.createTemp('g0_r0_path_');
    await databaseFactory.setDatabasesPath(dir.path);

    final uncaught = <Object>[];
    Object? thrown;
    await runZonedGuarded(() async {
      // 테스트 환경엔 MethodChannel 핸들러가 없어 getDeviceProtectedStoragePath가 MissingPluginException
      DatabaseService.debugIsAndroidOverride = true;
      try {
        await DatabaseService.instance.database;
      } catch (e) {
        thrown = e;
      }
      // 늦게 새는 비동기 오류가 있으면 이 사이에 잡힘
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }, (error, stack) => uncaught.add(error));

    expect(thrown, isA<MissingPluginException>(), reason: '경로 조회 실패를 삼키지 않고 호출자에게 전달해야 함');
    expect(uncaught, isEmpty, reason: '같은 실패가 처리되지 않은 비동기 오류로 한 번 더 새면 안 됨');
    expect(File('${dir.path}/shiftbell.db').existsSync(), isFalse, reason: '일반 경로로 대체해 새 DB를 만들면 안 됨');

    // 실패 후 Completer가 비워져 다음 호출이 새로 시도해야 함(Android가 아닌 경로 = 호스트 테스트 경로)
    DatabaseService.debugIsAndroidOverride = false;
    final db = await DatabaseService.instance.database;
    expect(await db.getVersion(), 24);
    expect(File('${dir.path}/shiftbell.db').existsSync(), isTrue);

    // 이미 열린 뒤에는 같은 인스턴스
    expect(identical(await DatabaseService.instance.database, db), isTrue);
  });
}
