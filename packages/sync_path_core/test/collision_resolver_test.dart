import 'dart:math';
import 'package:sync_path_core/sync_path_core.dart';
import 'package:test/test.dart';
import 'support/fixtures.dart';

// Independent oracle: exhaust all rational candidates with the proven q<=14.
SegmentContact exhaustiveContact(LinearPiece a, LinearPiece b) {
  if (a.start == b.start && a.end == b.end)
    return CoincidentInterval(Rational.zero, Rational.one);
  Rational? first;
  for (var q = 1; q <= 14; q++) {
    for (var p = 0; p <= q; p++) {
      bool equal(int s1, int e1, int s2, int e2) =>
          q * s1 + p * (e1 - s1) == q * s2 + p * (e2 - s2);
      if (equal(a.start.x, a.end.x, b.start.x, b.end.x) &&
          equal(a.start.y, a.end.y, b.start.y, b.end.y)) {
        final t = Rational(p, q);
        if (first == null || t.compareTo(first) < 0) first = t;
      }
    }
  }
  if (first == null) return const NoContact();
  final p = first.numerator, q = first.denominator;
  return InstantContact(
    first,
    RationalPoint(
      Rational(q * a.start.x + p * (a.end.x - a.start.x), q),
      Rational(q * a.start.y + p * (a.end.y - a.start.y), q),
    ),
  );
}

void sameContact(SegmentContact a, SegmentContact b) {
  expect(a.runtimeType, b.runtimeType);
  if (a is InstantContact && b is InstantContact) {
    expect(a.time, b.time);
    expect(a.position, b.position);
  }
  if (a is CoincidentInterval && b is CoincidentInterval) {
    expect(a.startTime, b.startTime);
    expect(a.endTime, b.endTime);
  }
}

void main() {
  const resolver = CollisionResolver();
  for (final vector in fixture('10_collision_fixtures.json')['vectors']) {
    test(vector['id'] as String, () {
      final a = LinearPiece(
        'A',
        1,
        cell(vector['startA']),
        cell(vector['endA']),
      );
      final b = LinearPiece(
        'B',
        1,
        cell(vector['startB']),
        cell(vector['endB']),
      );
      final expected = vector['expected'];
      final actual = resolver.resolve(a, b);
      if (expected == null) {
        expect(actual, isA<NoContact>());
      } else if (expected['interval'] == true) {
        expect(actual, isA<CoincidentInterval>());
      } else {
        sameContact(
          actual,
          InstantContact(
            fraction(expected['time']),
            point(expected['position']),
          ),
        );
      }
      sameContact(actual, exhaustiveContact(a, b));
      sameContact(actual, resolver.resolve(b, a));
      Cell rotate(Cell c) => Cell(7 - c.y, c.x);
      final rotated = resolver.resolve(
        LinearPiece('A', 1, rotate(a.start), rotate(a.end)),
        LinearPiece('B', 1, rotate(b.start), rotate(b.end)),
      );
      expect(rotated.runtimeType, actual.runtimeType);
      if (actual is InstantContact) {
        sameContact(
          rotated,
          InstantContact(
            actual.time,
            RationalPoint(Rational(7) - actual.position.y, actual.position.x),
          ),
        );
        final reversed = resolver.resolve(
          LinearPiece('A', 1, a.end, a.start),
          LinearPiece('B', 1, b.end, b.start),
        );
        sameContact(
          reversed,
          InstantContact(Rational.one - actual.time, actual.position),
        );
      }
      Cell reflect(Cell c) => Cell(7 - c.x, c.y);
      final reflected = resolver.resolve(
        LinearPiece('A', 1, reflect(a.start), reflect(a.end)),
        LinearPiece('B', 1, reflect(b.start), reflect(b.end)),
      );
      expect(reflected.runtimeType, actual.runtimeType);
      if (actual is InstantContact)
        sameContact(
          reflected,
          InstantContact(
            actual.time,
            RationalPoint(Rational(7) - actual.position.x, actual.position.y),
          ),
        );
    });
  }
  test(
    '20,000 bounded segment pairs vs independent exhaustive oracle (seed 20261013)',
    () {
      final random = Random(20261013);
      Cell next() => Cell(random.nextInt(8), random.nextInt(8));
      for (var i = 0; i < 20000; i++) {
        final a = LinearPiece('A', 1, next(), next());
        final b = LinearPiece('B', 1, next(), next());
        sameContact(resolver.resolve(a, b), exhaustiveContact(a, b));
      }
    },
  );
  test('E15 multiple sites and three pairs are preserved and sorted', () {
    final collisions = earliestStepCollisions(const [
      LinearPiece('D', 1, Cell(2, 2), Cell(0, 2)),
      LinearPiece('B', 1, Cell(2, 0), Cell(0, 0)),
      LinearPiece('C', 1, Cell(0, 2), Cell(2, 2)),
      LinearPiece('A', 1, Cell(0, 0), Cell(2, 0)),
    ], const Cell(7, 7));
    expect(collisions.length, 2);
    expect(collisions.map((c) => c.unitIds), [
      ['A', 'B'],
      ['C', 'D'],
    ]);
    expect(collisions.map((c) => c.position.toJson()), [
      [
        [1, 1],
        [0, 1],
      ],
      [
        [1, 1],
        [2, 1],
      ],
    ]);
    final triples = earliestStepCollisions(const [
      LinearPiece('A', 1, Cell(0, 2), Cell(2, 2)),
      LinearPiece('B', 1, Cell(4, 2), Cell(2, 2)),
      LinearPiece('C', 1, Cell(2, 0), Cell(2, 2)),
    ], const Cell(7, 7));
    expect(triples.length, 3);
  });
}
