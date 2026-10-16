import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_ui/sync_path_ui.dart';
import 'support.dart' show enter, fromJson;
import 'prototype_test.dart' show visuals;

LevelPack campaign() => const LevelParser()
    .parsePack(
      File(
        '../../docs/next_version_27이후/game_implementation_v6/previous_30_pilot_levels.json',
      ).readAsStringSync(),
    )
    .value!;
List<dynamic> certificates() => jsonDecode(
  File(
    '../../docs/next_version_27이후/game_implementation_v4/level_verification.json',
  ).readAsStringSync(),
)['levels'];
Map<String, PuzzleCopy> copy() {
  final data =
      jsonDecode(
            File(
              '../../docs/next_version_27이후/game_implementation_v6/previous_30_pilot_copy.json',
            ).readAsStringSync(),
          )
          as Map;
  return {
    for (final id in data.keys)
      id as String: PuzzleCopy(
        data[id]['titleKo'],
        data[id]['titleEn'],
        List<String>.from(data[id]['hintsKo']),
        List<String>.from(data[id]['hintsEn']),
        chapterKo: data[id]['chapterKo'],
        chapterEn: data[id]['chapterEn'],
      ),
  };
}

Future<GameSessionController> session(int index, {double rate = 1.5}) async {
  final s = GameSessionController(
    campaign(),
    MemoryProgressStore(),
    unlockAllForTesting: true,
    playbackRate: rate,
  );
  await s.initialize();
  s.openLevel(index);
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '30 levels preserve safe witnesses, unique identities and six chapter targets',
    () async {
      final p = campaign(), proof = certificates(), words = copy();
      expect(p.levels.length, 30);
      expect(p.levels.map((l) => l.identity).toSet().length, 30);
      expect(words.values.where((c) => c.chapterKo != null).length, 6);
      for (var i = 0; i < 30; i++) {
        expect(
          words['L${(i + 1).toString().padLeft(2, '0')}']!.chapterKo != null,
          i % 5 == 0,
        );
        final s = await session(i);
        enter(s, fromJson(proof[i]['witness']['routes']));
        expect(s.canExecute, isTrue);
        s.execute();
        expect(s.trace!.outcome, SimulationOutcome.success);
        s.advance(const Duration(minutes: 1));
        expect(s.mode, SessionMode.successReview);
        expect(s.completedLevels, contains(p.levels[i].identity));
        s.dispose();
      }
      expect(proof.last['distinctSolutionCount'], 1);
    },
  );
  test(
    '1.5x applies one common clock; every trajectory, arrival and collision is unchanged',
    () async {
      for (final i in [3, 14, 29]) {
        final proof = certificates()[i];
        for (final routeJson in [
          proof['witness']['routes'],
          if (proof['failureExample'] != null)
            proof['failureExample']['routes'],
        ]) {
          final normal = await session(i, rate: 1), fast = await session(i);
          for (final s in [normal, fast]) {
            enter(s, fromJson(routeJson));
            s.execute();
          }
          expect(
            jsonEncode(fast.trace!.toJson()),
            jsonEncode(normal.trace!.toJson()),
          );
          normal.advance(const Duration(milliseconds: 900));
          fast.advance(const Duration(milliseconds: 600));
          expect(
            fast.replay!.position,
            closeTo(normal.replay!.position, 1e-10),
          );
          final a = const MovementPresentation().frame(normal),
              b = const MovementPresentation().frame(fast);
          for (var k = 0; k < a.units.length; k++) {
            expect(
              a.units[k].position.x,
              closeTo(b.units[k].position.x, 1e-10),
            );
            expect(
              a.units[k].position.y,
              closeTo(b.units[k].position.y, 1e-10),
            );
          }
          for (final cue in b.cues) {
            final matching = a.cues.firstWhere(
              (x) =>
                  x.kind == cue.kind && x.unitIds.join() == cue.unitIds.join(),
            );
            expect(
              cue.age.inMicroseconds,
              closeTo(matching.age.inMicroseconds / 1.5, 1),
            );
          }
          normal.dispose();
          fast.dispose();
        }
      }
    },
  );
  testWidgets('Level cards open tutorial and final level directly', (
    tester,
  ) async {
    final s = await session(0);
    s.leave();
    await tester.pumpWidget(SyncPathGameApp(session: s, copy: copy()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('level-0')));
    await tester.pumpAndSettle();
    expect(s.levelIndex, 0);
    s.leave();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('level-29')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('level-29')));
    await tester.pumpAndSettle();
    expect(s.levelIndex, 29);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
  testWidgets(
    'Late chapters render 4/5 characters and 8-column boards at 320/412 px',
    (tester) async {
      await tester.runAsync(() async {
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
      final directory = Directory(
        '../../docs/next_version_27이후/game_implementation_v11/legacy_previews/historical30',
      )..createSync(recursive: true);
      for (final (width, index) in [
        (320.0, 15),
        (320.0, 29),
        (412.0, 23),
        (412.0, 29),
      ]) {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        final s = await session(index),
            art = await tester.runAsync(visuals),
            key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: SyncPathGameApp(session: s, copy: copy(), visuals: art!),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
        for (final u in s.level.units)
          expect(find.byKey(ValueKey('unit-${u.id}')), findsOneWidget);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${directory.path}/L${index + 1}-${width.toInt()}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        enter(s, fromJson(certificates()[index]['witness']['routes']));
        await tester.pump();
        await tester.ensureVisible(find.byKey(const ValueKey('execute')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('execute')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 30));
        expect(s.mode, SessionMode.successReview);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        s.dispose();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
