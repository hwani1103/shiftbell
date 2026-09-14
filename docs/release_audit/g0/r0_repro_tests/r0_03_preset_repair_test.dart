// R0-03 — 프리셋 복구 중 부분 실패 뒤 재시도하면 ID 1·2·3이 모두 복구되어야 한다.
//
// 수정 전 기대 결과(FAIL 이유): c06ffea는 ID 1 insert가 autocommit된 뒤 ID 2가 실패하면,
// 다음 open에서 presetCount > 0만 보고 복구를 건너뛴다. 최종 ID가 [1]이라 assertion 실패.
//
// 수정 후 기대 결과: 복구 묶음이 원자적으로 롤백되거나, 재시도에서 각 필수 ID의 존재를
// 따로 확인해 보충한다. 일시 실패 trigger를 제거한 뒤 최종 ID는 [1, 2, 3]이다.
import 'dart:async';
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

  test('R0-03: 두 번째 프리셋 insert 실패 뒤 재시도가 전체 프리셋을 완성한다', () async {
    final dir = await Directory.systemTemp.createTemp('r0_03_');
    final path = '${dir.path}${Platform.pathSeparator}shiftbell.db';
    final pathGate = Completer<String>();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Database? reopened;

    final fixture = await openDatabase(
      path,
      version: 24,
      singleInstance: false,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE alarm_types(
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            emoji TEXT NOT NULL,
            sound_file TEXT NOT NULL,
            volume REAL NOT NULL,
            vibration_strength INTEGER DEFAULT 2,
            is_preset INTEGER NOT NULL,
            duration INTEGER DEFAULT 10
          )
        ''');
        await db.execute('''
          CREATE TRIGGER fail_preset_2
          BEFORE INSERT ON alarm_types
          WHEN NEW.id = 2
          BEGIN
            SELECT RAISE(ABORT, 'injected preset insert failure');
          END
        ''');
      },
    );
    await fixture.close();

    await messenger.setMockMethodCallHandler(kAlarmChannel, (call) async {
      if (call.method == 'getDeviceProtectedStoragePath') return pathGate.future;
      return null;
    });
    addTearDown(() async {
      await messenger.setMockMethodCallHandler(kAlarmChannel, null);
      await reopened?.close();
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    // 두 번째 호출자가 공유 Completer의 오류를 구독하게 한 뒤 경로를 넘긴다. 이 테스트가
    // R0-04의 미처리 오류에 먼저 중단되지 않고 프리셋 원자성만 보게 한다.
    final firstOpen = _observe(DatabaseService.instance.database);
    final secondOpen = _observe(DatabaseService.instance.database);
    pathGate.complete(path);
    final firstResults = await Future.wait<Object>([firstOpen, secondOpen]);
    expect(firstResults.whereType<Database>(), isEmpty, reason: '주입한 ID 2 insert 실패는 open 실패로 전파되어야 함');

    // 저장공간 확보 같은 일시 원인 제거를 모사한다. 제품 복구 로직이나 테이블 내용은
    // 손대지 않고 실패 trigger만 제거한다.
    final raw = await openDatabase(path, singleInstance: false);
    await raw.execute('DROP TRIGGER fail_preset_2');
    await raw.close();

    reopened = await DatabaseService.instance.database;
    final ids = (await reopened!.rawQuery(
      'SELECT id FROM alarm_types WHERE is_preset = 1 ORDER BY id',
    ))
        .map((row) => row['id'])
        .toList();

    expect(ids, <Object?>[1, 2, 3], reason: '재시도 성공은 일부가 아니라 필수 프리셋 전체를 보장해야 함');
  });
}

