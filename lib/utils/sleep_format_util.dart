import 'package:intl/intl.dart';
import '../models/sleep_record.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/generated/app_localizations_ko.dart';

const List<String> kWeekdayLabelsKo = ['월', '화', '수', '목', '금', '토', '일'];

String fmtWeekday(DateTime date, {AppLocalizations? localizations}) =>
    localizations == null || localizations.localeName.startsWith('ko')
        ? kWeekdayLabelsKo[date.weekday - 1]
        : DateFormat.E(localizations.localeName).format(date);

String fmtDateWeekday(DateTime date, {AppLocalizations? localizations}) =>
    localizations == null || localizations.localeName.startsWith('ko')
        ? '${date.month}/${date.day} (${fmtWeekday(date)})'
        : DateFormat.MMMEd(localizations.localeName).format(date);

String fmtDateTime(DateTime date, {AppLocalizations? localizations}) =>
    '${fmtShortSleepDate(date, localizations: localizations)} ${fmtTimeOnly(date, localizations: localizations)}';

String fmtShortSleepDate(DateTime date, {AppLocalizations? localizations}) =>
    localizations == null || localizations.localeName.startsWith('ko')
        ? '${date.month}/${date.day}'
        : DateFormat.MMMd(localizations.localeName).format(date);

// Compact sleep timelines use an unambiguous 24-hour clock in every language.
String fmtTimeOnly(DateTime date, {AppLocalizations? localizations}) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String fmtDuration(Duration duration, {AppLocalizations? localizations}) {
  final copy = localizations ?? AppLocalizationsKo();
  final hours = duration.inMinutes ~/ 60;
  final minutes = duration.inMinutes % 60;
  if (hours <= 0) return copy.sleepText075(minutes.toString());
  if (minutes == 0) return copy.sleepText076(hours.toString());
  return copy.sleepText077(hours.toString(), minutes.toString());
}

String fmtMinutesAsClock(int minutes) =>
    '${((minutes ~/ 60) % 24).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

String fmtSleepDuration(Duration duration, SleepSource source,
        {AppLocalizations? localizations}) =>
    fmtDuration(duration, localizations: localizations);
