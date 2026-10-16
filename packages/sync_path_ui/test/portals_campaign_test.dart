import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_ui/sync_path_ui.dart';
import 'gates_campaign_test.dart' show current, open, currentCopy;
import 'compact_ui_test.dart' show tap;
import 'support.dart' show enter, fromJson;

const evidence = '../../docs/next_version_27이후/game_implementation_v10';
Map<String, dynamic> proof() =>
    jsonDecode(File('$evidence/portal_verification.json').readAsStringSync());
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (name, path) in [
      ('packages/sync_path_ui/GameSans', 'assets/fonts/GameSansSubset.ttf'),
      (
        'MaterialIcons',
        'C:/tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ]) {
      final loader = FontLoader(name)
        ..addFont(
          Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
        );
      await loader.load();
    }
  });
  test(
    'Existing fifty gameplay levels and progress identity preserved; v11 removes titles',
    () {
      final old = jsonDecode(
        File('$evidence/previous_50_pilot_levels.json').readAsStringSync(),
      );
      final live = jsonDecode(
        File(
          '../../examples/sync_path_lab/assets/pilot_levels.json',
        ).readAsStringSync(),
      );
      expect(live['packId'], old['packId']);
      expect(live['revision'], old['revision']);
      expect((live['levels'] as List).take(50).toList(), old['levels']);
      final oldCopy = jsonDecode(
        File('$evidence/previous_50_pilot_copy.json').readAsStringSync(),
      );
      final copy = jsonDecode(
        File(
          '../../examples/sync_path_lab/assets/pilot_copy.json',
        ).readAsStringSync(),
      );
      for (final k in oldCopy.keys) {
        expect(copy[k].containsKey('titleKo'), isFalse);
        expect(copy[k].containsKey('titleEn'), isFalse);
        expect(copy[k]['hintsKo'].length, oldCopy[k]['hintsKo'].length);
        expect(copy[k]['hintsEn'].length, oldCopy[k]['hintsEn'].length);
      }
    },
  );
  test(
    'Every portal witness is editable, reaches all goals, fixed velocity and undo from exit',
    () async {
      for (var i = 50; i < 70; i++) {
        final s = await open(i);
        final rs = fromJson(proof()['levels'][i - 50]['witness']);
        for (final r in rs) {
          s.selectUnit(r.unitId);
          for (final end in r.endpoints) {
            expect(s.append(end), isTrue);
            expect(s.currentFor(r.unitId), s.level.afterEndpoint(end));
            if (s.level.portalAt(end) != null) {
              final before = s.routes
                  .firstWhere((v) => v.unitId == r.unitId)
                  .endpoints
                  .length;
              s.undo();
              expect(
                s.routes
                    .firstWhere((v) => v.unitId == r.unitId)
                    .endpoints
                    .length,
                before - 1,
              );
              expect(s.append(end), isTrue);
              expect(s.currentFor(r.unitId), s.level.portalAt(end)!.exit);
            }
          }
        }
        expect(s.canExecute, isTrue);
        s.execute();
        expect(s.trace!.outcome, SimulationOutcome.success);
        expect(s.trace!.portals, isNotEmpty);
        for (final p in s.trace!.motions) {
          expect(
            p.durationUnits,
            (p.end.x - p.start.x).abs() + (p.end.y - p.start.y).abs(),
          );
        }
        s.advance(const Duration(minutes: 1));
        expect(s.mode, SessionMode.successReview);
        s.dispose();
      }
    },
  );
  test(
    'Replay jumps exactly at transfer with no midpoint and identical frame schedules',
    () async {
      final s = await open(50);
      enter(s, fromJson(proof()['levels'][0]['witness']));
      s.execute();
      final trace = s.trace!, e = trace.portals.first;
      final cursor = ReplayCursor(trace);
      cursor.seek(e.timeUnits.toDouble());
      expect(cursor.centers[e.unitId]!.x, e.exit.x.toDouble());
      expect(cursor.centers[e.unitId]!.y, e.exit.y.toDouble());
      cursor.seek(e.timeUnits - .001);
      final before = cursor.centers[e.unitId]!;
      expect(
        (before.x - e.entry.x).abs() + (before.y - e.entry.y).abs(),
        lessThan(.002),
      );
      final one = ReplayCursor(trace), many = ReplayCursor(trace);
      one.advance(const Duration(milliseconds: 6500));
      for (var i = 0; i < 100; i++) {
        many.advance(const Duration(milliseconds: 65));
      }
      expect(many.position, closeTo(one.position, 1e-8));
      expect(many.completed, one.completed);
      s.dispose();
    },
  );
  test(
    'Simultaneous entry and exit contacts keep the transferring ball at IN',
    () {
      final l = LevelSpec(
        identity: const LevelIdentity(
          'test',
          'double-contact',
          1,
          constantSpeedRuleSet,
        ),
        map: GridMap(width: 5, height: 5, rows: List.filled(5, '.....')),
        goal: const Cell(4, 4),
        units: const [
          UnitSpec('A', Cell(0, 3)),
          UnitSpec('B', Cell(4, 3)),
          UnitSpec('C', Cell(4, 0)),
        ],
        maxCommands: 5,
        portals: const [PortalPair('1', Cell(2, 3), Cell(2, 0))],
        requiredMechanics: const [
          'straight-motion',
          'absorbing-shared-goal',
          'endpoint-portals',
        ],
      );
      final trace =
          const SimulationEngine().simulate(
                l,
                RoutePlan(l.identity, [
                  UnitRoute('A', const [Cell(2, 3), Cell(4, 0), Cell(4, 4)]),
                  UnitRoute('B', const [Cell(0, 3), Cell(0, 4), Cell(4, 4)]),
                  UnitRoute('C', const [Cell(0, 0), Cell(0, 4), Cell(4, 4)]),
                ]),
              )
              as SimulationTrace;
      expect(trace.earliestCollisions.length, 2);
      expect(trace.portals, isEmpty);
      final cursor = ReplayCursor(trace)..seek(2);
      expect(cursor.centers['A']!.x, 2);
      expect(cursor.centers['A']!.y, 3);
      expect(cursor.centers['B']!.y, 3);
      expect(cursor.centers['C']!.y, 0);
    },
  );
  testWidgets(
    'Portal levels do not interrupt play; all four help pages stay available',
    (t) async {
      final store = MemoryProgressStore();
      final s = GameSessionController(
        current(),
        store,
        unlockAllForTesting: true,
      );
      await s.initialize();
      s.markRulesSeen(gates: true);
      s.openLevel(50);
      await t.pumpWidget(SyncPathGameApp(session: s, showIntro: true));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tap(t, 'game-menu');
      await tap(t, 'menu-help');
      for (var i = 0; i < 4; i++) {
        expect(find.text('${i + 1}/4'), findsOneWidget);
        expect(find.text(const GameStrings().lessonTitles[i]), findsOneWidget);
        expect(find.byKey(const ValueKey('hint')), findsNothing);
        await tap(t, 'help-next');
      }
      expect(find.byType(AlertDialog), findsNothing);
      await s.flush();
      await t.pumpWidget(const SizedBox());
      s.dispose();
      final restored = GameSessionController(
        current(),
        store,
        unlockAllForTesting: true,
      );
      await restored.initialize();
      expect(restored.portalRulesSeen, isFalse);
      expect(restored.gateRulesSeen, isTrue);
      restored.dispose();
    },
  );
  testWidgets('Paused replay can restart from the game menu', (t) async {
    final s = await open(50);
    enter(s, fromJson(proof()['levels'][0]['witness']));
    await t.pumpWidget(SyncPathGameApp(session: s));
    s.execute();
    await t.pump();
    await tap(t, 'game-menu');
    expect(s.mode, SessionMode.paused);
    await tap(t, 'menu-restart');
    expect(s.mode, SessionMode.planning);
    expect(s.trace, isNull);
    expect(s.routes.every((r) => r.endpoints.isEmpty), isTrue);
    await t.pumpWidget(const SizedBox());
    s.dispose();
  });
  testWidgets(
    'Portal collision stays on the contact, failure supports fresh restart',
    (t) async {
      final s = await open(51);
      enter(s, fromJson(proof()['levels'][1]['collisionFailure']));
      await t.pumpWidget(SyncPathGameApp(session: s));
      s.execute();
      s.advance(const Duration(minutes: 1));
      await t.pumpAndSettle();
      expect(s.mode, SessionMode.failureReview);
      for (final c in s.trace!.earliestCollisions) {
        for (final id in c.unitIds) {
          final point = s.replay!.centers[id]!;
          expect(point.x, c.position.x.toDouble());
          expect(point.y, c.position.y.toDouble());
        }
      }
      await tap(t, 'restart');
      expect(s.mode, SessionMode.planning);
      await t.pumpWidget(const SizedBox());
      s.dispose();
    },
  );
  testWidgets(
    'Portal and mixed maps render at 320x600 with stable board, light/dark/reduced motion',
    (t) async {
      t.view.physicalSize = const Size(320, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      for (final (i, skin) in [
        (50, GameSkin.light),
        (54, GameSkin.light),
        (59, GameSkin.light),
        (69, GameSkin.light),
        (69, GameSkin.dark),
      ]) {
        final s = await open(i);
        final key = GlobalKey();
        final rs = fromJson(proof()['levels'][i - 50]['witness']);
        final portalRoute = rs.firstWhere(
          (r) => r.endpoints.any((e) => s.level.portalAt(e) != null),
        );
        s.selectUnit(portalRoute.unitId);
        for (final e in portalRoute.endpoints) {
          s.append(e);
          if (s.level.portalAt(e) != null) break;
        }
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: SyncPathGameApp(
              session: s,
              skin: skin,
              copy: currentCopy(),
              visuals: BoardVisuals(
                unit: RollingBallVisual(),
                tile: BlockTileVisual(),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final top = t.getTopLeft(find.byType(GameBoard));
        expect(
          t.getRect(find.byKey(const ValueKey('execute'))).bottom,
          lessThanOrEqualTo(600),
        );
        expect(
          t
              .getRect(find.byKey(ValueKey('cell-${s.level.map.width - 1}-0')))
              .right,
          lessThanOrEqualTo(320),
        );
        await t.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          const output = String.fromEnvironment(
            'SYNC_PATH_UI_PREVIEW_DIR',
            defaultValue:
                '../../docs/next_version_27이후/game_implementation_v11/regression_previews/portals',
          );
          final f = File(
            '$output/L${i + 1}${skin == GameSkin.dark ? '-dark' : ''}.png',
          );
          await f.parent.create(recursive: true);
          await f.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        s.restart();
        enter(s, rs);
        s.execute(reducedMotion: true);
        await t.pumpAndSettle();
        expect(t.getTopLeft(find.byType(GameBoard)), top);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        s.dispose();
      }
    },
  );
}
