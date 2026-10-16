/// One persistent pool per level. Recovery starts only after exhaustion, then
/// continues until full, including after spending a partially refilled heart.
final class LevelHearts {
  static const capacity = 3;
  static const creditPerHeart =
      3600000000; // one background hour in microseconds
  int available;
  bool recovering;
  int credit;
  LevelHearts({
    this.available = capacity,
    this.recovering = false,
    this.credit = 0,
  });

  bool spend() {
    if (available == 0) return false;
    available--;
    if (available == 0) recovering = true;
    return true;
  }

  void elapse(Duration elapsed, {required bool foreground}) {
    if (!recovering || elapsed.isNegative) return;
    credit += elapsed.inMicroseconds * (foreground ? 60 : 1);
    while (credit >= creditPerHeart && available < capacity) {
      available++;
      credit -= creditPerHeart;
    }
    if (available == capacity) {
      recovering = false;
      credit = 0;
    }
  }

  double get fraction => recovering ? credit / creditPerHeart : 0;
  int secondsToNext({required bool foreground}) => recovering
      ? ((creditPerHeart - credit) / (foreground ? 60000000 : 1000000)).ceil()
      : 0;
  Map<String, Object> toJson() => {
    'available': available,
    'recovering': recovering,
    'credit': credit,
  };
  static LevelHearts? restore(Object? value) {
    if (value is! Map) return null;
    final n = value['available'], c = value['credit'], r = value['recovering'];
    if (n is! int ||
        n < 0 ||
        n > capacity ||
        c is! int ||
        c < 0 ||
        c >= creditPerHeart ||
        r is! bool ||
        (n == capacity && (r || c != 0)) ||
        (n == 0 && !r) ||
        (!r && c != 0)) {
      return null;
    }
    return LevelHearts(available: n, recovering: r, credit: c);
  }
}
