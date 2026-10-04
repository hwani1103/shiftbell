// Host-only stage measurements. These are not phone startup benchmarks.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:shiftbell/services/memo_category_classifier.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('large synthetic DB reopen and classifier cold load preserve data', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('startup_profile_');
    await databaseFactory.setDatabasesPath(dir.path);
    DatabaseService.debugIsAndroidOverride = false;
    final timings = <String, int>{};
    final watch = Stopwatch()..start();
    final db = await DatabaseService.instance.database;
    timings['empty_db_open_ms'] = watch.elapsedMilliseconds;
    try {
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (var i = 0; i < 20000; i++) {
          batch.insert('date_memos', {'date': DateTime(2000, 1, 1).add(Duration(days: i)).toIso8601String().substring(0, 10),
            'memo_text': 'Synthetic memo $i for host startup audit',
            'order_index': 0, 'created_at': '2026-10-03T00:00:00'});
        }
        await batch.commit(noResult: true);
      });
      watch.reset();
      final copy = await openDatabase(db.path, singleInstance: false);
      expect((await copy.rawQuery('SELECT COUNT(*) FROM date_memos')).single.values.single, 20000);
      expect((await copy.rawQuery('PRAGMA integrity_check')).single.values.single, 'ok');
      timings['large_db_second_connection_count_integrity_ms'] = watch.elapsedMilliseconds;
      await copy.close();
      final classifier = MemoCategoryClassifier.instance;
      expect(classifier.isLoaded, isFalse);
      watch.reset();
      final load = classifier.ensureLoaded();
      expect(identical(load, classifier.ensureLoaded()), isTrue);
      await load;
      timings['classifier_cold_load_ms'] = watch.elapsedMilliseconds;
      expect(classifier.classify('엄마한테 전화하기').categoryKey, 'family');
      watch.reset();
      await classifier.ensureLoaded();
      timings['classifier_warm_load_ms'] = watch.elapsedMilliseconds;
      // Captured by the JSON reporter; no hardware-dependent speed threshold.
      print('HOST_STAGE_PROFILE ${jsonEncode(timings)}');
    } finally {
      await db.close();
      DatabaseService.debugIsAndroidOverride = null;
      await dir.delete(recursive: true);
    }
  });
}
