import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/calendar_theme.dart';
import 'package:shiftbell/widgets/fold_calendar_text_scale.dart';

void main() {
  test('bar phone only: simple line and soft card use the 1.15 target', () {
    for (final scale in [1.0, 1.15, 1.3, 1.6]) {
      for (final theme in [
        CalendarThemeId.minimal,
        CalendarThemeId.materialCard
      ]) {
        expect(
            calendarShiftTextScaler(theme, TextScaler.linear(scale),
                    isBarPhone: true)
                .scale(10),
            closeTo(11.5, .001));
        expect(
            calendarShiftTextScaler(theme, TextScaler.linear(scale)).scale(10),
            closeTo(13, .001));
      }
    }
    expect(
        calendarShiftTextScaler(
                CalendarThemeId.initialBadge, TextScaler.noScaling,
                isBarPhone: true)
            .scale(10),
        13);
    expect(
        calendarShiftTextScaler(
                CalendarThemeId.mainWhite, const TextScaler.linear(1.2),
                isBarPhone: true)
            .scale(10),
        12);
  });
}
