import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/utils/alarm_dismiss_gate.dart';

void main() {
  test('a rapid repeat cannot cancel the alarm replacing the first card',
      () async {
    var now = DateTime(2026, 10, 12, 12);
    final gate = AlarmDismissGate(now: () => now);
    final pending = Completer<void>();
    final cancelled = <int>[];

    final first = gate.run(() async {
      cancelled.add(31);
      await pending.future;
    });
    expect(await gate.run(() async => cancelled.add(32)), isFalse);
    pending.complete();
    expect(await first, isTrue);

    // The card may already show ID 32 when the second pointer event arrives.
    expect(await gate.run(() async => cancelled.add(32)), isFalse);
    expect(cancelled, [31]);

    now = now.add(AlarmDismissGate.cooldown);
    expect(await gate.run(() async => cancelled.add(32)), isTrue);
    expect(cancelled, [31, 32]);
  });
}
