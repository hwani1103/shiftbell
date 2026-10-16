import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:sync_path_ui/sync_path_ui.dart';
import 'support.dart';

void main() {
  test(
    'Planning endpoint markers never move the physical Units or jump back on Execute',
    () async {
      final s = await session(8);
      addTearDown(s.dispose);
      enter(s, fromJson(certificates()['levels'][8]['witness']));
      final before = const MovementPresentation().frame(s);
      s.execute();
      final after = const MovementPresentation().frame(s);
      for (var i = 0; i < s.level.units.length; i++) {
        expect(before.units[i].position.x, s.level.units[i].start.x);
        expect(before.units[i].position.y, s.level.units[i].start.y);
        expect(after.units[i].position.x, before.units[i].position.x);
        expect(after.units[i].position.y, before.units[i].position.y);
      }
    },
  );
  test(
    'Every pilot success/failure render cursor matches exact core motion including all collision pairs',
    () async {
      final all = pilot(), cert = certificates()['levels'] as List;
      var checked = 0;
      for (var i = 0; i < all.levels.length; i++) {
        for (final routeData in [
          cert[i]['witness'],
          if (cert[i]['failureExample'] != null)
            cert[i]['failureExample']['routes'],
        ]) {
          final s = await session(i);
          enter(s, fromJson(routeData));
          s.execute();
          final trace = s.trace!;
          final original = jsonEncode(trace.toJson());
          final cursor = ReplayCursor(trace);
          for (
            var tick = 0;
            tick <= trace.durationInSteps.toDouble() * 120;
            tick++
          ) {
            final t = Rational(tick, 120);
            cursor.seek(t.toDouble());
            final positions = cursor.centers;
            for (final id in positions.keys) {
              final piece = trace.motions
                  .where(
                    (p) =>
                        p.unitId == id &&
                        Rational(p.step - 1).compareTo(t) <= 0,
                  )
                  .last;
              final local = t - Rational(piece.step - 1);
              final exact = piece.positionAt(
                local.compareTo(Rational.one) > 0 ? Rational.one : local,
              );
              expect(
                positions[id]!.x,
                closeTo(exact.x.toDouble(), 1e-10),
                reason: '${all.levels[i].identity.levelId} $id t=$t',
              );
              expect(positions[id]!.y, closeTo(exact.y.toDouble(), 1e-10));
              checked++;
            }
          }
          cursor.seek(cursor.end);
          for (final collision in trace.earliestCollisions) {
            for (final id in collision.unitIds) {
              expect(
                cursor.centers[id]!.x,
                closeTo(collision.position.x.toDouble(), 1e-10),
              );
              expect(
                cursor.centers[id]!.y,
                closeTo(collision.position.y.toDouble(), 1e-10),
              );
            }
          }
          expect(jsonEncode(trace.toJson()), original);
          s.dispose();
        }
      }
      expect(checked, greaterThan(10000));
    },
  );
}
