/// Keeps a rapid repeat tap on a replaced alarm card from dismissing the next
/// alarm. The lock starts when the first action finishes, so slow DB/OS work
/// cannot let a queued tap through during a card transition.
class AlarmDismissGate {
  AlarmDismissGate({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const cooldown = Duration(milliseconds: 700);
  final DateTime Function() _now;
  DateTime? _blockedUntil;
  bool _running = false;

  Future<bool> run(Future<void> Function() action) async {
    if (_running ||
        (_blockedUntil != null && _now().isBefore(_blockedUntil!))) {
      return false;
    }
    _running = true;
    try {
      await action();
      return true;
    } finally {
      _blockedUntil = _now().add(cooldown);
      _running = false;
    }
  }
}
