import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/widgets/shift_name_text_field.dart';

void main() {
  test('Hangul six, English sixteen, mixed Hangul six', () {
    expect(validateShiftName('주간근무추가'), isNull);
    expect(validateShiftName('주간근무추가분'), ShiftNameIssue.tooLong);
    expect(validateShiftName('Afternoon Shift'), isNull);
    expect(validateShiftName('1234567890123456'), isNull);
    expect(validateShiftName('12345678901234567'), ShiftNameIssue.tooLong);
    expect(validateShiftName('Day주간근무'), ShiftNameIssue.tooLong);
  });
  test('Korean IME composition completes before truncating', () {
    final formatter = ShiftNameLengthFormatter();
    const composing = TextEditingValue(text: '주간근무추가분',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 6, end: 7));
    expect(formatter.formatEditUpdate(TextEditingValue.empty, composing), composing);
    final committed = formatter.formatEditUpdate(composing,
        composing.copyWith(composing: TextRange.empty));
    expect(committed.text, '주간근무추가');
    expect(committed.selection.extentOffset, 6);
  });
  testWidgets('replace Korean with English and return across app locales', (tester) async {
    final controller = TextEditingController(text: '주간근무');
    addTearDown(controller.dispose);
    for (final locale in [const Locale('ko'), const Locale('en'), const Locale('ko')]) {
      await tester.pumpWidget(MaterialApp(locale: locale, home: Scaffold(
          body: ShiftNameTextField(controller: controller,
              decoration: const InputDecoration(labelText: 'Shift')))));
      await tester.enterText(find.byType(TextField), 'Afternoon Shift');
      await tester.pump();
      expect(controller.text, 'Afternoon Shift');
      expect(tester.widget<TextField>(find.byType(TextField)).maxLength, 16);
      await tester.enterText(find.byType(TextField), '주간근무추가분');
      await tester.pump();
      expect(controller.text, '주간근무추가');
      expect(tester.widget<TextField>(find.byType(TextField)).maxLength, 6);
      expect(tester.takeException(), isNull);
    }
  });
}
