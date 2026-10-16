import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/widgets/shift_chip_label.dart';

void main() {
  testWidgets('calendar labels reserve ratio padding and shrink long names',
      (tester) async {
    Future<(double, Rect)> draw(String name, Size size,
        {ShiftChipProportions proportions =
            ShiftChipProportions.calendarReview}) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(
        child: SizedBox(
            key: const ValueKey('chip'),
            width: size.width,
            height: size.height,
            child: ShiftChipLabel(label: name, proportions: proportions)),
      ))));
      final text = tester.widget<Text>(find.text(name));
      final chip = tester.getRect(find.byKey(const ValueKey('chip')));
      final rect = tester.getRect(find.text(name));
      expect(rect.height,
          lessThanOrEqualTo(size.height * proportions.heightFraction + .01));
      expect(
          rect.left, greaterThanOrEqualTo(chip.left + size.width * .05 - .01));
      expect(
          rect.right, lessThanOrEqualTo(chip.right - size.width * .05 + .01));
      expect(rect.center.dx, closeTo(chip.center.dx, .01));
      expect(rect.center.dy, closeTo(chip.center.dy, .01));
      expect(tester.takeException(), isNull);
      return (text.style!.fontSize!, rect);
    }

    final short = await draw('주간', const Size(90, 24));
    final doubled = await draw('주간', const Size(180, 48));
    expect(doubled.$1 / short.$1, closeTo(2, .08));
    final diary = await draw('주간', const Size(90, 24),
        proportions: ShiftChipProportions.diaryCalendar);
    final event = await draw('주간', const Size(90, 24),
        proportions: ShiftChipProportions.eventCalendar);
    expect(diary.$1, lessThan(short.$1));
    expect(event.$1, greaterThan(short.$1));
    final one = await draw('주', const Size(40, 20),
        proportions: ShiftChipProportions.diaryCalendar);
    final two = await draw('주간', const Size(40, 20),
        proportions: ShiftChipProportions.diaryCalendar);
    final four = await draw('주간주간', const Size(40, 20),
        proportions: ShiftChipProportions.diaryCalendar);
    expect(one.$1, closeTo(two.$1, .02),
        reason: 'Character count alone must not change the height-based size');
    expect(four.$1, lessThan(two.$1),
        reason: 'Only a name exceeding the horizontal safe area shrinks');
    final long = await draw('Afternoon Shift', const Size(90, 24));
    expect(long.$1, lessThan(short.$1));
    for (final name in ['Early', 'Früh', 'Manhã', 'सुबह']) {
      await draw(name, const Size(90, 24));
    }
  });
}
