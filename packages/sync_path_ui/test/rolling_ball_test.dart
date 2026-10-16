import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_ui/sync_path_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final right = LinearPiece(
    'A',
    1,
    const Cell(0, 0),
    const Cell(2, 0),
    startTimeUnits: 0,
    endTimeUnits: 2,
  );
  final down = LinearPiece(
    'A',
    2,
    const Cell(2, 0),
    const Cell(2, 3),
    startTimeUnits: 2,
    endTimeUnits: 5,
  );
  final left = LinearPiece(
    'A',
    2,
    const Cell(2, 0),
    const Cell(0, 0),
    startTimeUnits: 2,
    endTimeUnits: 4,
  );
  test(
    'Ball uses both rolling axes, keeps turn orientation, and reverses exactly',
    () {
      final q = BallRotation.at([right], 'A', .1);
      final (x, y, _) = q.rotate(0, 0, 1);
      expect(x, greaterThan(0));
      expect(y, closeTo(0, 1e-12));
      final vertical = LinearPiece('A', 1, const Cell(0, 0), const Cell(0, 2));
      final (vx, vy, _) = BallRotation.at([vertical], 'A', .1).rotate(0, 0, 1);
      expect(vx, closeTo(0, 1e-12));
      expect(vy, greaterThan(0));
      final before = BallRotation.at([right], 'A', 2);
      final turn = BallRotation.at([right, down], 'A', 2);
      expect(
        [turn.w, turn.x, turn.y, turn.z],
        [before.w, before.x, before.y, before.z],
      );
      final reverse = BallRotation.at([right, left], 'A', 4);
      expect(reverse.w, closeTo(1, 1e-12));
      for (final value in [reverse.x, reverse.y, reverse.z]) {
        expect(value, closeTo(0, 1e-12));
      }
    },
  );
  test(
    'Absolute-time rotation is stable for seeking and unit-length at all samples',
    () {
      for (var tick = 0; tick <= 500; tick++) {
        final time = tick / 100;
        final q = BallRotation.at([right, down], 'A', time);
        expect(
          q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z,
          closeTo(1, 1e-12),
        );
        BallRotation.at([right, down], 'A', 5 - time);
        final seek = BallRotation.at([right, down], 'A', time);
        expect([seek.w, seek.x, seek.y, seek.z], [q.w, q.x, q.y, q.z]);
        final other = BallRotation.at([right, down], 'B', time);
        expect([other.w, other.x, other.y, other.z], [1, 0, 0, 0]);
      }
    },
  );
  testWidgets(
    'Five procedural surface patterns render across horizontal and vertical roll',
    (tester) async {
      await tester.runAsync(() async {
        final visual = RollingBallVisual();
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(GameSkin.light.background, BlendMode.src);
        final views = <List<int>>[];
        for (var row = 0; row < 4; row++) {
          for (var index = 0; index < 5; index++) {
            final rotation = switch (row) {
              0 => BallRotation.identity,
              1 => BallRotation.at([right], 'A', .25),
              2 => BallRotation.at([right], 'A', .5),
              _ => BallRotation.at([right, down], 'A', 2.25),
            };
            visual.paint(
              canvas,
              Offset(50 + index * 100, 45 + row * 85),
              90,
              UnitVisualFrame(
                unitId: String.fromCharCode(65 + index),
                paletteIndex: index,
                position: const DisplayPoint(0, 0),
                facing: UnitFacing.down,
                state: UnitVisualState.moving,
                moveProgress: .5,
                distanceCells: 2,
                durationUnits: 2,
                visualTime: Duration.zero,
                playing: false,
                reducedMotion: false,
                ballRotation: rotation,
              ),
              GameSkin.light,
            );
            final q = rotation.rotate(0, 0, 1);
            views.add([
              for (final value in [q.$1, q.$2, q.$3]) (value * 1000).round(),
            ]);
          }
        }
        expect(views[0], isNot(views[5]));
        final picture = recorder.endRecording();
        final image = await picture.toImage(500, 340);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final folder = Directory(
          '../../docs/next_version_27이후/game_implementation_v11/legacy_previews',
        )..createSync(recursive: true);
        await File(
          '${folder.path}/rolling-patterns.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
        visual.dispose();
      });
    },
  );
}
