// R0-01 — Device Protected 경로 조회 실패를 필수 초기화 오류로 취급한다.
//
// 수정 전 기대 결과(FAIL 이유): c06ffea는 PlatformException을 catch하고 일반 DB 경로로
// fallback한다. 두 database Future가 모두 성공하고 fallback shiftbell.db가 생성되어
// 아래의 "오류 2개 / 일반 DB 미생성" assertion이 실패한다.
//
// 수정 후 기대 결과: 두 동시 호출자가 같은 초기화 실패를 받고, credential-protected
// fallback shiftbell.db는 생성되지 않는다. 다음 StartupGate 재시도가 경로를 다시 조회한다.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../test/release_audit/g0/g0_support.dart';

Future<Object> _observe(Future<Database> future) async {
  try {
    return await future;
  } catch (error) {
    return error;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initFfi);

  test('R0-01: DP 경로 조회 실패가 일반 DB 성공으로 바뀌지 않는다', () async {
    final dir = await Directory.systemTemp.createTemp('r0_01_');
    await databaseFactory.setDatabasesPath(dir.path);
    final fallbackFile = File('${dir.path}${Platform.pathSeparator}shiftbell.db');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    await messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'getDeviceProtectedStoragePath') {
        throw PlatformException(code: 'dp_path_unavailable', message: 'injected');
      }
      return null;
    });

    final observed = await Future.wait<Object>([
      _observe(DatabaseService.instance.database),
      _observe(DatabaseService.instance.database),
    ]);

    addTearDown(() async {
      await messenger.setMockMethodCallHandler(kAlarmChannel, null);
      for (final db in observed.whereType<Database>().toSet()) {
        await db.close();
      }
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    expect(
      observed.whereType<Database>(),
      isEmpty,
      reason: 'DP 경로를 모르면 다른 저장소에 새 DB를 열지 말고 필수 초기화를 실패시켜야 함',
    );
    expect(
      observed.where((result) => result is! Database).length,
      2,
      reason: '동시 호출자 둘 다 같은 실패를 관찰해야 함',
    );
    expect(fallbackFile.existsSync(), isFalse, reason: 'credential-protected fallback DB 생성 금지');
  });
}
