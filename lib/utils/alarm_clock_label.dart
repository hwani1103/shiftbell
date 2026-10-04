import 'package:flutter/widgets.dart';
import '../l10n/l10n_extensions.dart';
import 'alarm_wall_time.dart';

String? alarmClockLabel(BuildContext context, DateTime date) =>
    switch (alarmClockOccurrence(date)) {
      1 => context.l10n.alarmClockFirstOccurrence,
      2 => context.l10n.alarmClockSecondOccurrence,
      _ => null,
    };
