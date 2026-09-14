// R0-04 — 첫 DB 초기화 실패는 호출자가 한 번만 관찰하고 Zone 미처리 오류를 만들지 않는다.
//
// 수정 전 기대 결과(FAIL 이유): c06ffea는 첫 호출자에게 rethrow하면서 구독자가 없는
// _initCompleter.future도 completeError한다. runZonedGuarded가 별도 오류 1개를 받아
// uncaughtErrors isEmpty assertion이 실패한다.
//
// 수정 후 기대 결과: 호출자는 다운그레이드 거부 오류를 받고, 동일 오류가 별도의 미처리
// Future로 복제되지 않아 uncaughtErrors가 비어 있다.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../test/release_audit/g0/g0_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initFfi);

  test('R0-04: 단독 첫 초기화 실패가 미처리 Completer 오류를 추가로 만들지 않는다', () async {
    final dir = await Directory.systemTemp.createTemp('r0_04_');
    final path = '${dir.path}${Platform.pathSeparator}shiftbell.db';
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    final futureDb = await openDatabase(
      path,
      version: 25,
      singleInstance: false,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE marker(id INTEGER PRIMARY KEY, value TEXT)');
      },
    );
    await futureDb.close();

    await messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'getDeviceProtectedStoragePath') return path;
      return null;
    });
    addTearDown(() async {
      await messenger.setMockMethodCallHandler(kAlarmChannel, null);
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    Object? awaitedError;
    final uncaughtErrors = <Object>[];
    final guarded = runZonedGuarded<Future<void>>(
      () async {
        try {
          await DatabaseService.instance.database;
        } catch (error) {
          awaitedError = error;
        }
        // completeError로 예약된 미처리 오류가 같은 Zone handler에 도달할 시간을 준다.
        await Future<void>.delayed(Duration.zero);
      },
      (error, stack) => uncaughtErrors.add(error),
    );
    await guarded;

    expect(awaitedError, isNotNull, reason: 'v25 → v24 다운그레이드는 호출자에게 실패해야 함');
    expect(
      uncaughtErrors,
      isEmpty,
      reason: '호출자가 처리한 초기화 실패를 구독자 없는 Completer 오류로 다시 보내면 안 됨',
    );
  });
}
