import 'package:sync_path_core/sync_path_core.dart';
import 'package:test/test.dart';

void main() {
  test('E01 sign, gcd, zero, equality/hash and exact arithmetic', () {
    expect(Rational(-6, -8), Rational(3, 4));
    expect(Rational(6, -8), Rational(-3, 4));
    expect(Rational(0, -7).toJson(), [0, 1]);
    expect(() => Rational(1, 0), throwsArgumentError);
    expect(Rational(1, 3) + Rational(1, 6), Rational(1, 2));
    expect(Rational(1, 3) - Rational(1, 6), Rational(1, 6));
    expect(Rational(2, 3) * Rational(3, 4), Rational(1, 2));
    expect({Rational(2, 4), Rational(1, 2)}.length, 1);
  });
  test('E01 exact order remains transitive across bounded fractions', () {
    final values = [
      for (var q = 1; q <= 14; q++)
        for (var p = -q; p <= q; p++) Rational(p, q),
    ]..sort();
    for (var i = 2; i < values.length; i++) {
      expect(values[i - 2].compareTo(values[i]), lessThanOrEqualTo(0));
    }
  });
}
