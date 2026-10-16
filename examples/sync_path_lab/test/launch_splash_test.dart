import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/launch_splash.dart';

void main() {
  testWidgets('One compact poster automatically gives way to the main screen', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(
        key: key,
        child: const GameLaunchSplash(
          child: MaterialApp(
            home: Scaffold(
              body: Text('level list', key: ValueKey('main-screen')),
            ),
          ),
        ),
      ),
    );
    await t.runAsync(
      () => precacheImage(
        const AssetImage(GameLaunchSplash.asset),
        t.element(find.byType(Image)),
      ),
    );
    await t.pump();
    expect(find.byKey(const ValueKey('launch-splash')), findsOneWidget);
    expect(find.byKey(const ValueKey('main-screen')), findsNothing);
    await t.runAsync(() async {
      final img =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        '../../docs/UI 완성도 개선/GAME-11_검증_2026-10-15/previews/splash-320.png',
      );
      file.parent.createSync(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      img.dispose();
    });
    await t.pump(const Duration(milliseconds: 1000));
    expect(find.byKey(const ValueKey('main-screen')), findsNothing);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('main-screen')), findsOneWidget);
    expect(find.byKey(const ValueKey('launch-splash')), findsNothing);
    await t.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('main-screen')), findsOneWidget);
    expect(File(GameLaunchSplash.asset).lengthSync(), lessThan(30000));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
