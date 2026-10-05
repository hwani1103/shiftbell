// models/date_overtime.dart

import 'package:flutter/widgets.dart';
import '../l10n/l10n_extensions.dart';

class DateOvertime {
  final int? id;
  final String date; // 'YYYY-MM-DD'
  final int minutes; // 30분 단위 누적
  final String updatedAt;

  DateOvertime({
    this.id,
    required this.date,
    required this.minutes,
    required this.updatedAt,
  });

  factory DateOvertime.fromMap(Map<String, dynamic> map) {
    return DateOvertime(
      id: map['id'],
      date: map['date'],
      minutes: map['minutes'],
      updatedAt: map['updated_at'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'minutes': minutes,
      'updated_at': updatedAt,
    };
  }
}

/// Compact durations with locally familiar units, shared by calendar totals.
String formatOvertimeMinutes(BuildContext context, int totalMinutes) {
  final l = context.l10n;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (totalMinutes <= 0) return l.durationCompactMinutes(0);
  if (hours > 0 && minutes > 0) {
    return '${l.durationCompactHours(hours)} ${l.durationCompactMinutes(minutes)}';
  }
  if (hours > 0) return l.durationCompactHours(hours);
  return l.durationCompactMinutes(minutes);
}
