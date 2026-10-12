import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/constants/layout_limits.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/screens/friend_list_screen.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:shiftbell/services/firebase_bootstrap.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('audit_friend_list_');
    await databaseFactory.setDatabasesPath(dir.path);
    DatabaseService.debugIsAndroidOverride = false;
    firebaseReady = false;
    for (var i = 0; i < 100; i++) {
      await DatabaseService.instance.insertFriend(
          name: '교대근무 친구 $i', ownerId: 'audit_density_$i', dataJson: null);
    }
  });
  tearDownAll(() async {
    await (await DatabaseService.instance.database).close();
    DatabaseService.debugIsAndroidOverride = null;
    await dir.delete(recursive: true);
  });
  for (final size in const [Size(320, 640), Size(600, 800)]) {
    for (final scale in [1.3, 2.0]) {
      testWidgets('100 friends scroll to last delete control with safe area $size scale $scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.view.padding = const FakeViewPadding(bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(bottom: 24);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        await tester.pumpWidget(ProviderScope(child: ScreenUtilInit(
          designSize: const Size(360,780),
          builder: (context, _) {
            ScreenUtil.configure(data: appContentMediaQuery(MediaQueryData.fromView(View.of(context))),
                designSize: const Size(360,780));
            return MaterialApp(locale: const Locale('ko'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
              home: const FriendListScreen());
          },
        )));
        for (var i = 0; i < 15; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
        final list = find.byType(ListView).last;
        final scroll = tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)).first);
        // Repeated jumps account for ListView's progressively estimated extent.
        for (var i = 0; i < 8; i++) {
          scroll.position.jumpTo(scroll.position.maxScrollExtent);
          await tester.pump();
        }
        final finalName = find.textContaining('교대근무 친구 99');
        expect(finalName, findsOneWidget);
        final tile = find.ancestor(of: finalName, matching: find.byType(ListTile));
        await Scrollable.ensureVisible(tester.element(tile), alignment: 1);
        await tester.pump();
        final delete = find.descendant(of: tile, matching: find.byIcon(Icons.delete_outline));
        expect(delete.hitTestable(), findsOneWidget);
        expect(tester.getRect(delete).bottom, lessThanOrEqualTo(size.height - 24));
        expect(tester.getRect(tile).bottom, lessThanOrEqualTo(size.height - 24 + 0.01));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
