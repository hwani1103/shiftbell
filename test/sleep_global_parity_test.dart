import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/models/sleep_record.dart';
import 'package:shiftbell/services/condition/condition_rule_engine.dart';
import 'package:shiftbell/services/condition/recovery_briefing_engine.dart';
import 'package:shiftbell/services/condition/shift_pattern_analyzer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final evidence = <Map<String, dynamic>>[];
  setUpAll(() async {
    for (final language in ['ko', 'en', 'de', 'pt', 'hi']) {
      await initializeDateFormatting(language);
    }
  });
  tearDownAll(() {
    final file =
        File('artifacts/sleep_global_2026_10_14/host_language_parity.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(evidence));
  });
  final patterns = [
    ['Day', 'Off', 'Off'],
    ['Evening', 'Day', 'Off'],
    ['Night', 'Off', 'Off'],
    ['Night', 'Night', 'Off'],
    ['Night', 'Night', 'Night', 'Night', 'Off'],
    ['Day', 'Evening', 'Night', 'Off'],
    ['Night'],
    ['Unknown', 'Night', 'Off'],
  ];
  final times = {
    'Day': const ShiftTimeRange(
        shiftName: 'Day', startMinutes: 420, endMinutes: 1140),
    'Evening': const ShiftTimeRange(
        shiftName: 'Evening', startMinutes: 900, endMinutes: 1380),
    'Night': const ShiftTimeRange(
        shiftName: 'Night', startMinutes: 1140, endMinutes: 420),
  };
  for (var p = 0; p < patterns.length; p++) {
    for (final hour in [0, 6, 10, 16, 18, 23]) {
      for (final sleepMinutes in [0, 119, 120, 480]) {
        test(
            'pattern $p / hour $hour / sleep $sleepMinutes: five-language parity',
            () {
          final now = DateTime(2026, 9, 22, hour);
          final schedule = ShiftSchedule(
              isRegular: true,
              pattern: patterns[p],
              todayIndex: 1 % patterns[p].length,
              startDate: DateTime(2026, 9, 22),
              shiftTypes: patterns[p].toSet().toList());
          final analyzer =
              ShiftPatternAnalyzer(schedule: schedule, shiftTimes: times);
          final base =
              ConditionRuleEngine(analyzer).evaluate(DateTime(2026, 9, 22));
          final records = <SleepRecord>[];
          if (sleepMinutes > 0) {
            for (var day = 1; day <= 12; day++) {
              final start = DateTime(2026, 9, 22 - day, 8);
              records.add(SleepRecord(
                  start: start,
                  end: start.add(Duration(minutes: sleepMinutes)),
                  source: SleepSource.manual,
                  status: SleepStatus.confirmed));
            }
          }
          final ko = buildRecoveryBriefing(
              analyzer: analyzer,
              base: base,
              records: records,
              now: now,
              pendingCount: 2);
          final entry = <String, dynamic>{
            'pattern': patterns[p],
            'hour': hour,
            'sleepMinutes': sleepMinutes,
            'level': ko.level.name,
            'phase': ko.phase.name,
            'languages': <String, dynamic>{}
          };
          for (final language in ['ko', 'en', 'de', 'pt', 'hi']) {
            final actual = buildRecoveryBriefing(
                analyzer: analyzer,
                base: base,
                records: records,
                now: now,
                pendingCount: 2,
                localizations: lookupAppLocalizations(Locale(language)));
            expect(actual.level, ko.level);
            expect(actual.phase, ko.phase);
            expect(actual.evidenceIds, ko.evidenceIds);
            expect(
                actual.actions.map((a) => a.id), ko.actions.map((a) => a.id));
            expect(
                actual.facts.map((a) => a.topic), ko.facts.map((a) => a.topic));
            expect(
                actual.facts.map((a) => a.tone), ko.facts.map((a) => a.tone));
            expect(actual.limitations.length, ko.limitations.length);
            final text = [
              actual.situation,
              ...actual.facts.map((f) => f.text),
              ...actual.actions.map((a) => a.text),
              ...actual.limitations
            ].join('\n');
            expect(text, isNot(contains('{arg')));
            expect(text, isNot(contains('null')));
            if (language != 'ko')
              expect(RegExp(r'[가-힣]').hasMatch(text), isFalse,
                  reason: language + ' ' + text);
            (entry['languages'] as Map<String, dynamic>)[language] = text;
          }
          evidence.add(entry);
        });
      }
    }
  }
}
