import '../model/models.dart';

/// Exact v1 arithmetic: callers keep integer inputs within the bounded grid.
final class Rational implements Comparable<Rational> {
  final int numerator;
  final int denominator;
  factory Rational(int numerator, [int denominator = 1]) {
    if (denominator == 0) throw ArgumentError.value(denominator, 'denominator');
    if (denominator < 0) {
      numerator = -numerator;
      denominator = -denominator;
    }
    final gcd = numerator.abs().gcd(denominator);
    return Rational._(numerator ~/ gcd, denominator ~/ gcd);
  }
  const Rational._(this.numerator, this.denominator);
  static final zero = Rational(0);
  static final one = Rational(1);
  Rational operator +(Rational other) => Rational(
    numerator * other.denominator + other.numerator * denominator,
    denominator * other.denominator,
  );
  Rational operator -(Rational other) => Rational(
    numerator * other.denominator - other.numerator * denominator,
    denominator * other.denominator,
  );
  Rational operator *(Rational other) =>
      Rational(numerator * other.numerator, denominator * other.denominator);
  Rational operator /(Rational other) =>
      Rational(numerator * other.denominator, denominator * other.numerator);
  @override
  int compareTo(Rational other) =>
      (numerator * other.denominator).compareTo(other.numerator * denominator);
  bool operator <(Rational other) => compareTo(other) < 0;
  bool operator >(Rational other) => compareTo(other) > 0;
  @override
  bool operator ==(Object other) =>
      other is Rational &&
      numerator == other.numerator &&
      denominator == other.denominator;
  @override
  int get hashCode => Object.hash(numerator, denominator);
  double toDouble() => numerator / denominator;
  List<int> toJson() => [numerator, denominator];
  @override
  String toString() => '$numerator/$denominator';
}

final class RationalPoint implements Comparable<RationalPoint> {
  final Rational x;
  final Rational y;
  const RationalPoint(this.x, this.y);
  factory RationalPoint.cell(Cell cell) =>
      RationalPoint(Rational(cell.x), Rational(cell.y));
  @override
  int compareTo(RationalPoint other) {
    final dx = x.compareTo(other.x);
    return dx == 0 ? y.compareTo(other.y) : dx;
  }

  @override
  bool operator ==(Object other) =>
      other is RationalPoint && x == other.x && y == other.y;
  @override
  int get hashCode => Object.hash(x, y);
  List<List<int>> toJson() => [x.toJson(), y.toJson()];
}
