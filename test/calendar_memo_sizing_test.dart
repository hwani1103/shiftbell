import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/widgets/calendar_memo_sizing.dart';

void main() {
  test('compact main dates use only two baselines based on two-memo clearance',
      () {
    List<double> paddings(double bodyHeight) => List.generate(
        4,
        (count) => CalendarMemoSizing.mainDateBottomPadding(
            count: count,
            bodyHeight: bodyHeight,
            dateHeight: 20,
            memoRowHeight: 10,
            bottomInset: 2,
            gap: 1));
    final roomy = paddings(68);
    expect(roomy.take(3), everyElement(0));
    expect(roomy[3], greaterThan(0));
    final compact = paddings(60);
    expect(compact.take(2), everyElement(0));
    expect(compact[2], greaterThan(0));
    expect(compact[2], compact[3]);
  });

  test(
      'shift-size cap targets balanced inner windows, not previous Fold tuning',
      () {
    for (final size in [const Size(752, 834.67), const Size(834.67, 752)]) {
      expect(CalendarMemoSizing.capsAtShiftSize(size), isTrue);
    }
    for (final size in [
      const Size(360, 840),
      const Size(475.43, 751.24),
      const Size(932.57, 704),
      const Size(704, 932.57)
    ]) {
      expect(CalendarMemoSizing.capsAtShiftSize(size), isFalse);
    }
  });
  test('wide proportions share the same three-line budget by count', () {
    for (final size in [const Size(932.57, 704), const Size(900, 760)]) {
      expect(CalendarMemoSizing.scaleFor(size, 1) / 3, .75);
      expect(CalendarMemoSizing.scaleFor(size, 2) * 2 / 3, 1);
      expect(CalendarMemoSizing.scaleFor(size, 3), 1);
    }
  });
  test('Fold cover reduces one and two memos without changing three', () {
    const cover = Size(475.43, 751.24);
    expect(CalendarMemoSizing.scaleFor(cover, 1), 1.5);
    expect(CalendarMemoSizing.scaleFor(cover, 2), (1.5 + 1) / 2);
    expect(CalendarMemoSizing.scaleFor(cover, 3), 1);
  });
  test('narrow phones and tall cover windows keep their original memo sizes',
      () {
    for (final size in [
      const Size(393, 852),
      const Size(360, 640),
      const Size(480, 800),
      const Size(430, 960),
      const Size(540, 1200)
    ]) {
      for (final count in [1, 2, 3]) {
        expect(CalendarMemoSizing.scaleFor(size, count), 1);
      }
    }
  });
}
