import 'package:flutter/widgets.dart';
import '../models/calendar_theme.dart';

/// These four themes start at their former maximum shift-label size.
/// Smaller system text can reduce it; larger system text cannot enlarge it.
TextScaler calendarShiftTextScaler(CalendarThemeId theme, TextScaler system,
    {bool isBarPhone = false}) {
  const enlarged = {
    CalendarThemeId.minimal,
    CalendarThemeId.materialCard,
    CalendarThemeId.initialBadge,
    CalendarThemeId.eventChip,
  };
  if (!enlarged.contains(theme)) return system;
  final target = isBarPhone &&
          (theme == CalendarThemeId.minimal ||
              theme == CalendarThemeId.materialCard)
      ? 1.15
      : 1.3;
  return TextScaler.linear(target * system.scale(1).clamp(0.0, 1.0));
}

/// Calendar cells retain three memo lines on narrow phones and foldables.
/// Cap only the calendar surface; the rest of the app keeps the system scale.
class FoldCalendarTextScale extends StatelessWidget {
  const FoldCalendarTextScale({super.key, required this.child});
  final Widget child;
  static const maxScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
          textScaler: media.textScaler.clamp(maxScaleFactor: maxScale)),
      child: child,
    );
  }
}
