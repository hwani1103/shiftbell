import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_ui/sync_path_ui.dart';
import 'package:sync_path_ui/src/gate_visual.dart';
import 'support.dart';
import 'compact_ui_test.dart' show tap;

const evidence = '../../docs/UI 완성도 개선/GAME-14_검증_2026-10-16';

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$evidence/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    for (final (name, path) in [
      ('packages/sync_path_ui/GameSans', 'assets/fonts/GameSansSubset.ttf'),
      (
        'MaterialIcons',
        'C:/tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ]) {
      await (FontLoader(name)..addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          ))
          .load();
    }
  });

  testWidgets(
    'Zero hearts blocks board, selection, undo and go until recovery',
    (t) async {
      var now = DateTime.utc(2026, 10, 16);
      final s = GameSessionController(
        pilot(),
        MemoryProgressStore(),
        clock: () => now,
      );
      await s.initialize();
      s.openLevel(0);
      for (var i = 0; i < 3; i++) {
        enter(s, fromJson(certificates()['levels'][0]['witness']));
        s.execute();
        s.advance(const Duration(minutes: 1));
        s.restart();
      }
      expect(s.hearts.available, 0);
      final key = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: SyncPathGameApp(session: s),
        ),
      );
      await t.pumpAndSettle();
      expect(s.destinations, isEmpty);
      final revision = s.routeRevision;
      await tap(t, 'cell-0-2');
      await tap(t, 'unit-B');
      s.selectUnit('B');
      s.toggleUnit('A');
      s.undo();
      s.clearSelected();
      s.execute();
      expect(s.selectedUnitId, 'A');
      expect(s.routeRevision, revision);
      expect(s.routes.every((r) => r.endpoints.isEmpty), true);
      expect(s.mode, SessionMode.planning);
      expect(
        t
            .widget<OutlinedButton>(find.byKey(const ValueKey('unit-A')))
            .style!
            .backgroundColor!
            .resolve({}),
        GameSkin.light.disabledSurface,
      );
      expect(
        t
            .widget<OutlinedButton>(find.byKey(const ValueKey('unit-B')))
            .onPressed,
        isNull,
      );
      expect(
        t.widget<OutlinedButton>(find.byKey(const ValueKey('undo'))).onPressed,
        isNull,
      );
      expect(
        t.widget<FilledButton>(find.byKey(const ValueKey('execute'))).onPressed,
        isNull,
      );
      expect(find.textContaining('다음 하트'), findsNothing);
      await capture(t, key, 'empty-hearts');
      now = now.add(const Duration(seconds: 60));
      await t.pump(const Duration(seconds: 1));
      expect(s.hearts.available, 1);
      expect(s.editable, true);
      await tap(t, 'cell-0-2');
      expect(s.routes.first.endpoints, [const Cell(0, 2)]);
      await t.pumpWidget(const SizedBox());
      s.dispose();
    },
  );

  test(
    'Last selected route dots disappear during replay, pause and review',
    () async {
      final s = await session(0);
      enter(s, fromJson(certificates()['levels'][0]['witness']));
      final gates = GateVisual();
      final painter = GameBoardPainter(s, GameSkin.light, gates: gates);
      int dots() {
        final canvas = TestRecordingCanvas();
        painter.paint(canvas, const Size(300, 300));
        return canvas.invocations
            .where(
              (r) =>
                  r.invocation.memberName == #drawCircle &&
                  r.invocation.positionalArguments[1] == 3,
            )
            .length;
      }

      expect(dots(), greaterThan(0));
      s.execute();
      expect(dots(), 0);
      s.pause();
      expect(dots(), 0);
      s.resume();
      s.advance(const Duration(minutes: 1));
      expect(dots(), 0);
      gates.dispose();
      s.dispose();
    },
  );

  for (final korean in [true, false]) {
    testWidgets(
      'Four general help pages and back navigation at 320px ($korean)',
      (t) async {
        t.view.physicalSize = const Size(320, 600);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final s = await session(0);
        final words = GameStrings(korean: korean);
        final key = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: SyncPathGameApp(
              session: s,
              strings: words,
              copy: {
                s.level.identity.levelId: const PuzzleCopy(
                  '',
                  '',
                  ['SECRET'],
                  ['SECRET'],
                ),
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        await tap(t, 'game-menu');
        await tap(t, 'menu-help');
        expect(
          t
              .widget<TextButton>(find.byKey(const ValueKey('help-back')))
              .onPressed,
          isNull,
        );
        for (var page = 0; page < 4; page++) {
          expect(find.text('${page + 1}/4'), findsOneWidget);
          expect(find.text(words.lessonTitles[page]), findsOneWidget);
          expect(find.text('SECRET'), findsNothing);
          expect(find.byKey(const ValueKey('hint')), findsNothing);
          expect(find.text(words.next), findsNothing);
          expect(t.takeException(), isNull);
          expect(
            find.byKey(const ValueKey('help-next')).hitTestable(),
            findsOneWidget,
          );
          await capture(t, key, 'help-${korean ? 'ko' : 'en'}-${page + 1}');
          if (page > 0) {
            await tap(t, 'help-back');
            expect(find.text('$page/4'), findsOneWidget);
            await tap(t, 'help-next');
          }
          await tap(t, 'help-next');
        }
        expect(find.byType(AlertDialog), findsNothing);
        // Reading normal help must not consume the first-Lv1 introduction.
        expect(s.rulesSeen, false);
        await t.pumpWidget(const SizedBox());
        s.dispose();
      },
    );
  }
}
