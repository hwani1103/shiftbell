import '../math/rational.dart';
import '../model/models.dart';

final class LinearPiece {
  final String unitId;
  final int step;
  final Cell start;
  final Cell end;
  final int? _startTimeUnits, _endTimeUnits;
  const LinearPiece(
    this.unitId,
    this.step,
    this.start,
    this.end, {
    int? startTimeUnits,
    int? endTimeUnits,
  }) : _startTimeUnits = startTimeUnits,
       _endTimeUnits = endTimeUnits;
  int get startTimeUnits => _startTimeUnits ?? step - 1;
  int get endTimeUnits => _endTimeUnits ?? step;
  int get durationUnits => endTimeUnits - startTimeUnits;
  RationalPoint positionAtGlobal(Rational time) =>
      positionAt((time - Rational(startTimeUnits)) / Rational(durationUnits));
  RationalPoint positionAt(Rational time) => RationalPoint(
    Rational(start.x) + Rational(end.x - start.x) * time,
    Rational(start.y) + Rational(end.y - start.y) * time,
  );
  Map<String, Object> toJson() => {
    'unitId': unitId,
    'step': step,
    'start': start.toJson(),
    'end': end.toJson(),
    if (_startTimeUnits != null) 'startTimeUnits': startTimeUnits,
    if (_endTimeUnits != null) 'endTimeUnits': endTimeUnits,
  };
}

sealed class SegmentContact {
  const SegmentContact();
}

/// Exact contacts in absolute logical time. Each piece may have a different
/// command ordinal and duration. No pixels or animation clocks enter here.
final class TemporalCollisionResolver {
  const TemporalCollisionResolver();
  SegmentContact resolve(LinearPiece a, LinearPiece b) {
    if (a.durationUnits <= 0 || b.durationUnits <= 0)
      throw ArgumentError('Positive motion duration required');
    final begin = a.startTimeUnits > b.startTimeUnits
        ? a.startTimeUnits
        : b.startTimeUnits;
    final end = a.endTimeUnits < b.endTimeUnits
        ? a.endTimeUnits
        : b.endTimeUnits;
    if (begin > end) return const NoContact();
    final ap = a.positionAtGlobal(Rational(begin));
    final bp = b.positionAtGlobal(Rational(begin));
    final rx = ap.x - bp.x, ry = ap.y - bp.y;
    final vx =
        Rational(a.end.x - a.start.x, a.durationUnits) -
        Rational(b.end.x - b.start.x, b.durationUnits);
    final vy =
        Rational(a.end.y - a.start.y, a.durationUnits) -
        Rational(b.end.y - b.start.y, b.durationUnits);
    if (vx == Rational.zero && vy == Rational.zero) {
      return rx == Rational.zero && ry == Rational.zero
          ? CoincidentInterval(Rational(begin), Rational(end))
          : const NoContact();
    }
    final dt = vx != Rational.zero
        ? (Rational.zero - rx) / vx
        : (Rational.zero - ry) / vy;
    if (dt < Rational.zero ||
        dt > Rational(end - begin) ||
        rx + vx * dt != Rational.zero ||
        ry + vy * dt != Rational.zero)
      return const NoContact();
    final time = Rational(begin) + dt;
    return InstantContact(time, a.positionAtGlobal(time));
  }
}

bool temporalGoalContact(
  SegmentContact c,
  LinearPiece a,
  LinearPiece b,
  Cell goal,
) =>
    c is InstantContact &&
    c.position == RationalPoint.cell(goal) &&
    c.time == Rational(a.endTimeUnits) &&
    c.time == Rational(b.endTimeUnits) &&
    a.end == goal &&
    b.end == goal;

List<CollisionEvent> earliestTemporalCollisions(
  List<LinearPiece> pieces,
  Cell goal,
) {
  final events = <CollisionEvent>[];
  final seen = <String>{};
  Rational? earliest;
  for (var i = 0; i < pieces.length; i++) {
    for (var j = i + 1; j < pieces.length; j++) {
      final a = pieces[i], b = pieces[j];
      if (a.unitId == b.unitId) continue;
      final contact = const TemporalCollisionResolver().resolve(a, b);
      if (contact is NoContact || temporalGoalContact(contact, a, b, goal))
        continue;
      final time = switch (contact) {
        InstantContact(:final time) => time,
        CoincidentInterval(:final startTime) => startTime,
        NoContact() => throw StateError('Unreachable'),
      };
      if (earliest == null || time.compareTo(earliest) < 0) {
        earliest = time;
        events.clear();
        seen.clear();
      }
      if (time != earliest) continue;
      final step = time == Rational.zero
          ? 1
          : (time.numerator + time.denominator - 1) ~/ time.denominator;
      final event = CollisionEvent(
        step,
        time - Rational(step - 1),
        a.positionAtGlobal(time),
        a.unitId,
        b.unitId,
      );
      final key = '${event.position.toJson()}|${event.unitIds}';
      if (seen.add(key)) events.add(event);
    }
  }
  events.sort((a, b) {
    var order = a.position.compareTo(b.position);
    if (order == 0) order = a.unitIds[0].compareTo(b.unitIds[0]);
    if (order == 0) order = a.unitIds[1].compareTo(b.unitIds[1]);
    return order;
  });
  return List.unmodifiable(events);
}

final class NoContact extends SegmentContact {
  const NoContact();
}

final class InstantContact extends SegmentContact {
  final Rational time;
  final RationalPoint position;
  const InstantContact(this.time, this.position);
}

final class CoincidentInterval extends SegmentContact {
  final Rational startTime;
  final Rational endTime;
  const CoincidentInterval(this.startTime, this.endTime);
}

/// Geometry only: neither Goal nor sprites nor frame rates affect contact.
final class CollisionResolver {
  const CollisionResolver();
  SegmentContact resolve(LinearPiece a, LinearPiece b) {
    if (a.step != b.step)
      throw ArgumentError('Pieces must belong to the same Step');
    for (final cell in [a.start, a.end, b.start, b.end]) {
      if (cell.x < 0 || cell.x > 7 || cell.y < 0 || cell.y > 7)
        throw ArgumentError('Geometry is bounded to the v1 grid (0..7)');
    }
    final rx = a.start.x - b.start.x;
    final ry = a.start.y - b.start.y;
    final vx = (a.end.x - a.start.x) - (b.end.x - b.start.x);
    final vy = (a.end.y - a.start.y) - (b.end.y - b.start.y);
    if (vx == 0 && vy == 0) {
      return rx == 0 && ry == 0
          ? CoincidentInterval(Rational.zero, Rational.one)
          : const NoContact();
    }
    final t = vx != 0 ? Rational(-rx, vx) : Rational(-ry, vy);
    if (t.compareTo(Rational.zero) < 0 || t.compareTo(Rational.one) > 0)
      return const NoContact();
    final p = t.numerator;
    final q = t.denominator;
    if (q * rx + p * vx != 0 || q * ry + p * vy != 0) return const NoContact();
    return InstantContact(t, a.positionAt(t));
  }
}

final class CollisionPolicy {
  const CollisionPolicy();

  /// Only apply to pieces compiled from validated complete v1 routes.
  bool allows(SegmentContact contact, Cell goal) =>
      contact is InstantContact &&
      contact.time == Rational.one &&
      contact.position == RationalPoint.cell(goal);
}

final class CollisionEvent {
  final int step;
  final Rational localTime;
  final RationalPoint position;
  final List<String> unitIds;
  CollisionEvent(this.step, this.localTime, this.position, String a, String b)
    : unitIds = List.unmodifiable([a, b]..sort());
  Rational get globalTime => Rational(step - 1) + localTime;
  Map<String, Object> toJson() => {
    'step': step,
    'localTime': localTime.toJson(),
    'globalTime': globalTime.toJson(),
    'position': position.toJson(),
    'unitIds': unitIds,
  };
}

/// Resolves an entire Step and preserves every pair at its earliest forbidden time.
List<CollisionEvent> earliestStepCollisions(
  List<LinearPiece> pieces,
  Cell goal,
) {
  final events = <CollisionEvent>[];
  Rational? earliest;
  for (var i = 0; i < pieces.length; i++) {
    for (var j = i + 1; j < pieces.length; j++) {
      final a = pieces[i];
      final b = pieces[j];
      final contact = const CollisionResolver().resolve(a, b);
      if (contact is NoContact || const CollisionPolicy().allows(contact, goal))
        continue;
      final time = switch (contact) {
        InstantContact(:final time) => time,
        CoincidentInterval(:final startTime) => startTime,
        NoContact() => throw StateError('Unreachable'),
      };
      if (earliest == null || time.compareTo(earliest) < 0) {
        earliest = time;
        events.clear();
      }
      if (time == earliest)
        events.add(
          CollisionEvent(a.step, time, a.positionAt(time), a.unitId, b.unitId),
        );
    }
  }
  events.sort((a, b) {
    var order = a.globalTime.compareTo(b.globalTime);
    if (order == 0) order = a.position.compareTo(b.position);
    if (order == 0) order = a.unitIds[0].compareTo(b.unitIds[0]);
    if (order == 0) order = a.unitIds[1].compareTo(b.unitIds[1]);
    return order;
  });
  return List.unmodifiable(events);
}
