import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_path_ui/sync_path_ui.dart';
import 'support.dart';

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final textLoader = FontLoader('packages/sync_path_ui/GameSans');
    final textBytes = File('assets/fonts/GameSansSubset.ttf').readAsBytesSync();
    textLoader.addFont(Future.value(ByteData.sublistView(textBytes)));
    await textLoader.load();
    final icons = FontLoader('MaterialIcons');
    final iconBytes = File(
      'C:/tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ).readAsBytesSync();
    icons.addFont(Future.value(ByteData.sublistView(iconBytes)));
    await icons.load();
  });
  for (final width in [320.0, 360.0, 412.0, 736.0]) {
    testWidgets(
      'U07 ${width.toInt()}px planning/undo/success/back with no overflow and reachable controls',
      (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final s = await session(0);
        addTearDown(s.dispose);
        await tester.pumpWidget(SyncPathGameApp(session: s));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(s.selectedUnitId, 'A');
        await tapKey(tester, 'cell-0-2');
        await tapKey(tester, 'cell-2-2');
        expect(s.selectedUnitId, 'B');
        await tapKey(tester, 'unit-A');
        await tapKey(tester, 'undo');
        expect(s.selectedUnitId, 'A');
        await tapKey(tester, 'cell-2-2');
        expect(s.selectedUnitId, 'B');
        await tapKey(tester, 'cell-4-2');
        await tapKey(tester, 'cell-2-2');
        expect(s.canExecute, isTrue);
        await tapKey(tester, 'execute');
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(s.mode, SessionMode.successReview);
        expect(tester.takeException(), isNull);
        await tapKey(tester, 'exit');
        expect(s.mode, SessionMode.hub);
        expect(s.completedLevels.length, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'U02 board taps another Unit start as a destination; drag does not add a command',
    (tester) async {
      final s = await session(6);
      addTearDown(s.dispose);
      await tester.pumpWidget(SyncPathGameApp(session: s));
      await tester.pumpAndSettle();
      await tapKey(tester, 'cell-1-0');
      expect(s.routes.first.endpoints.single.x, 1);
      expect(s.selectedUnitId, 'A');
      final revision = s.routeRevision;
      final from = tester.getCenter(find.byKey(const ValueKey('cell-1-0')));
      final to = tester.getCenter(find.byKey(const ValueKey('cell-0-0')));
      final gesture = await tester.startGesture(from);
      await gesture.moveTo(to);
      await gesture.up();
      await tester.pump();
      expect(s.routeRevision, revision);
    },
  );
  testWidgets('Lower buttons select balls; board centers remain route inputs', (
    tester,
  ) async {
    final s = await session(0);
    addTearDown(s.dispose);
    await tester.pumpWidget(SyncPathGameApp(session: s));
    await tester.pumpAndSettle();
    expect(s.selectedUnitId, 'A');
    await tapKey(tester, 'unit-A');
    await tapKey(tester, 'cell-0-0');
    expect(s.selectedUnitId, isNull);
    expect(s.routes.first.endpoints, isEmpty);
    await tapKey(tester, 'unit-A');
    expect(s.selectedUnitId, 'A');
    await tapKey(tester, 'cell-0-2');
    await tapKey(tester, 'cell-0-0');
    expect(s.selectedUnitId, 'A');
    expect(s.routes.first.endpoints.length, 2);
    expect(s.routes.first.endpoints.last, s.level.units.first.start);
    final revision = s.routeRevision;
    await tapKey(tester, 'unit-B');
    expect(s.selectedUnitId, 'B');
    expect(s.routeRevision, revision);
    expect(s.routes.first.endpoints.length, 2);
    await tapKey(tester, 'unit-B');
    expect(s.selectedUnitId, isNull);
    await tapKey(tester, 'unit-A');
    expect(s.selectedUnitId, 'A');
    await tapKey(tester, 'unit-A');
    expect(s.selectedUnitId, isNull);
    await tapKey(tester, 'unit-B');
    expect(s.selectedUnitId, 'B');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('U04 menu path edits preserve routes after failure', (
    tester,
  ) async {
    final s = await session(8);
    addTearDown(s.dispose);
    enter(s, fromJson(certificates()['levels'][8]['failureExample']['routes']));
    await tester.pumpWidget(SyncPathGameApp(session: s));
    await tester.pumpAndSettle();
    await tapKey(tester, 'execute');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(s.mode, SessionMode.failureReview);
    expect(s.trace!.earliestCollisions.length, 3);
    final lengths = s.routes.map((r) => r.endpoints.length).toList();
    await tapKey(tester, 'game-menu');
    await tester.pumpAndSettle();
    await tapKey(tester, 'menu-edit');
    await tester.pumpAndSettle();
    if (s.selectedUnitId == 'C') {
      await tapKey(tester, 'unit-C');
      expect(s.selectedUnitId, isNull);
    }
    await tapKey(tester, 'unit-C');
    expect(s.mode, SessionMode.planning);
    expect(s.selectedUnitId, 'C');
    expect(s.routes.map((r) => r.endpoints.length).toList(), lengths);
  });
  testWidgets(
    'U08 reduced motion remains paused without timers and permits manual scenes',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final s = await session(0);
      addTearDown(s.dispose);
      enter(s, fromJson(certificates()['levels'][0]['witness']));
      await tester.pumpWidget(SyncPathGameApp(session: s));
      await tester.pumpAndSettle();
      await tapKey(tester, 'execute');
      await tester.pump(const Duration(seconds: 5));
      expect(s.mode, SessionMode.paused);
      expect(s.replay!.position, 0);
      await tapKey(tester, 'resume');
      expect(s.replay!.position, 1);
      await tapKey(tester, 'resume');
      expect(s.mode, SessionMode.successReview);
    },
  );
  testWidgets(
    'U09 lifecycle pauses replay; return does not start ticker automatically',
    (tester) async {
      final s = await session(0);
      addTearDown(s.dispose);
      enter(s, fromJson(certificates()['levels'][0]['witness']));
      await tester.pumpWidget(SyncPathGameApp(session: s));
      await tester.pumpAndSettle();
      await tapKey(tester, 'execute');
      await tester.pump(const Duration(milliseconds: 100));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final position = s.replay!.position;
      await tester.pump(const Duration(seconds: 10));
      expect(s.replay!.position, position);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(s.mode, SessionMode.paused);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(s.mode, SessionMode.hub);
    },
  );
  testWidgets(
    'Role palette, 6x6 cells, fixed text scaling and controls at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 680);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final s = await session(11);
      addTearDown(s.dispose);
      await tester.pumpWidget(
        SyncPathGameApp(
          session: s,
          skin: GameSkin.dark,
          strings: const GameStrings(korean: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('cell-0-0'))).width,
        greaterThanOrEqualTo(44),
      );
      final context = tester.element(find.byType(GameBoard));
      expect(MediaQuery.textScalerOf(context).scale(14), 14);
      expect(Theme.of(context).brightness, Brightness.dark);
      await tester.ensureVisible(find.byKey(const ValueKey('execute')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Capture independent planning screens at narrow/wide and dark palette',
    (tester) async {
      final artifact = Directory(
        '../../docs/next_version_27이후/game_implementation_v11/regression_previews/basic',
      )..createSync(recursive: true);
      for (final (width, dark, i) in [
        (320.0, false, 0),
        (412.0, false, 8),
        (736.0, false, 11),
        (320.0, true, 11),
      ]) {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        final s = await session(i);
        enter(s, fromJson(certificates()['levels'][i]['witness']));
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: SyncPathGameApp(
              key: ValueKey('$width-$dark'),
              session: s,
              skin: dark ? GameSkin.dark : GameSkin.light,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${artifact.path}/planning-${width.toInt()}-${dark ? 'dark' : 'light'}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox());
        s.dispose();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
