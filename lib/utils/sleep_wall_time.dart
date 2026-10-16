/// All real instants matching user-entered local clock fields.
/// Empty = a skipped DST time; two = a repeated time needing an explicit choice.
/// UTC [wall] is only a container for civil fields, never an instant to save.
List<DateTime> sleepWallTimeCandidates(DateTime wall,
    {DateTime Function(int)? localFromEpoch}) {
  final local = localFromEpoch ??
      (int millis) => DateTime.fromMillisecondsSinceEpoch(millis);
  final fields =
      DateTime.utc(wall.year, wall.month, wall.day, wall.hour, wall.minute);
  final epoch = fields.millisecondsSinceEpoch;
  final offsets = {-2, 0, 2}
      .map((days) =>
          local(epoch + days * Duration.millisecondsPerDay).timeZoneOffset)
      .toSet();
  final candidates = <DateTime>[];
  for (final offset in offsets) {
    final candidate = local(epoch - offset.inMilliseconds);
    if (candidate.year == wall.year &&
        candidate.month == wall.month &&
        candidate.day == wall.day &&
        candidate.hour == wall.hour &&
        candidate.minute == wall.minute) {
      candidates.add(candidate);
    }
  }
  return candidates..sort((a, b) => a.compareTo(b));
}

String sleepUtcOffset(DateTime value) {
  final minutes = value.timeZoneOffset.inMinutes;
  return 'UTC${minutes < 0 ? '-' : '+'}${(minutes.abs() ~/ 60).toString().padLeft(2, '0')}:${(minutes.abs() % 60).toString().padLeft(2, '0')}';
}
