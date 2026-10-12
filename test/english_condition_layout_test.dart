import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/screens/english_condition_tab.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dbDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dbDir = await Directory.systemTemp.createTemp('english_condition_layout_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    DatabaseService.debugIsAndroidOverride = false;
    await DatabaseService.instance.database;
  });

  tearDownAll(() async {
    await DatabaseService.instance.database.then((db) => db.close());
    DatabaseService.debugIsAndroidOverride = null;
    if (dbDir.existsSync()) await dbDir.delete(recursive: true);
  });

  testWidgets('영어 수면 화면은 접힌 폭과 펼친 폭에서 큰 글씨에도 넘치지 않는다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 2.625; // 420dpi 폴더블 AVD
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final width in [884.0, 1768.0]) {
      tester.view.physicalSize = Size(width, 2208);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: EnglishConditionTab(
            onDisabled: () {},
            onConfirmed: () async {},
          ),
        ),
      ));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 100));
      // Async DB read uses a real isolate; keep pumping until the content replaces loading.
      for (var attempt = 0;
          attempt < 20 &&
              find
                  .text('Your sleep')
                  .evaluate()
                  .isEmpty;
          attempt++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Sleep & Recovery'), findsOneWidget);
      // The same ListView keeps its scroll position when the simulated fold opens.
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
      await tester.pump();
      expect(find.text('Your sleep'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'width=$width');
      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pumpAndSettle();
      expect(
          find.text('Stop using the Sleep & Recovery screen'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'button at width=$width');
    }
  });
}
