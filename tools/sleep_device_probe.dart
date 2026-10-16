// Explicit Android test entry point. Never used by lib/main.dart or release builds.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/shift_time_range.dart';
import 'package:shiftbell/models/sleep_record.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:shiftbell/services/condition/shift_pattern_analyzer.dart';
import 'package:shiftbell/services/condition/sleep_day_slots.dart';
import 'package:shiftbell/services/condition/condition_rule_engine.dart';
import 'package:shiftbell/services/condition/recovery_briefing_engine.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/utils/sleep_wall_time.dart';
import 'sleep_release_cases.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final evidence = <String, Object?>{};
  final errors = <String>[];
  for (final language in ['ko', 'en', 'de', 'pt', 'hi']) {
    await initializeDateFormatting(language);
  }
  final policy = runSleepReleaseCases();
  evidence['attribution'] = policy;
  errors.addAll((policy['errors'] as List<String>));
  void check(String name, Object? actual, Object? expected) {
    (evidence['clockChecks'] as List).add({'name': name, 'actual': actual,
      'expected': expected, 'pass': actual == expected});
    if (actual != expected) errors.add(name);
  }
  evidence['clockChecks'] = <Map<String, Object?>>[];
  evidence['legacySQLiteObservations'] = <Map<String, Object?>>[];
  final patterns = [
    ['Day', 'Off', 'Off'], ['Evening', 'Day', 'Off'],
    ['Night', 'Off', 'Off'], ['Night', 'Night', 'Off'],
    ['Night', 'Night', 'Night', 'Night', 'Off'],
    ['Day', 'Evening', 'Night', 'Off'], ['Night'], ['Unknown', 'Night', 'Off'],
  ];
  final times = {
    'Day': const ShiftTimeRange(shiftName: 'Day', startMinutes: 420, endMinutes: 1140),
    'Evening': const ShiftTimeRange(shiftName: 'Evening', startMinutes: 900, endMinutes: 1380),
    'Night': const ShiftTimeRange(shiftName: 'Night', startMinutes: 1140, endMinutes: 420),
  };
  final parity = <Map<String, Object?>>[];
  for (var p = 0; p < patterns.length; p++) {
    for (final hour in [0, 6, 10, 16, 18, 23]) {
      for (final minutes in [0, 119, 120, 480]) {
        final now = DateTime(2026, 9, 22, hour);
        final analyzer = ShiftPatternAnalyzer(schedule: ShiftSchedule(isRegular: true,
          pattern: patterns[p], todayIndex: 1 % patterns[p].length,
          startDate: DateTime(2026, 9, 22), shiftTypes: patterns[p].toSet().toList()), shiftTimes: times);
        final base = ConditionRuleEngine(analyzer).evaluate(DateTime(2026, 9, 22));
        final records = <SleepRecord>[];
        if (minutes > 0) {
          for (var day = 1; day <= 12; day++) {
            final start = DateTime(2026, 9, 22 - day, 8);
            records.add(SleepRecord(start: start, end: start.add(Duration(minutes: minutes)),
              source: SleepSource.manual, status: SleepStatus.confirmed));
          }
        }
        final ko = buildRecoveryBriefing(analyzer: analyzer, base: base, records: records,
          now: now, pendingCount: 2);
        final output = <String, String>{};
        for (final language in ['ko', 'en', 'de', 'pt', 'hi']) {
          final actual = buildRecoveryBriefing(analyzer: analyzer, base: base, records: records,
            now: now, pendingCount: 2, localizations: lookupAppLocalizations(Locale(language)));
          final expectedIds = jsonEncode([ko.level.name, ko.phase.name, ko.evidenceIds,
            ko.actions.map((x) => x.id).toList(), ko.facts.map((x) => x.topic.name).toList(),
            ko.facts.map((x) => x.tone.name).toList(), ko.limitations.length]);
          final actualIds = jsonEncode([actual.level.name, actual.phase.name, actual.evidenceIds,
            actual.actions.map((x) => x.id).toList(), actual.facts.map((x) => x.topic.name).toList(),
            actual.facts.map((x) => x.tone.name).toList(), actual.limitations.length]);
          final text = [actual.situation, ...actual.facts.map((x) => x.text),
            ...actual.actions.map((x) => x.text), ...actual.limitations].join('\n');
          if (actualIds != expectedIds || (language != 'ko' && RegExp(r'[가-힣]').hasMatch(text)) ||
              text.contains('{arg') || text.contains('null')) {
            errors.add('parity ' + [p, hour, minutes, language].join('/'));
          }
          output[language] = text;
        }
        parity.add({'pattern': p, 'hour': hour, 'minutes': minutes, 'languages': output});
      }
    }
  }
  evidence['languageParity'] = parity;
  final janOffset = DateTime(2026, 1, 15).timeZoneOffset.inMinutes;
  final julOffset = DateTime(2026, 7, 15).timeZoneOffset.inMinutes;
  evidence['zone'] = {'name': DateTime.now().timeZoneName, 'januaryOffset': janOffset,
    'julyOffset': julOffset};
  // Real device-local constructors, independent of the host timezone package.
  final transitions = switch ((janOffset, julOffset)) {
    (-300, -240) => [(3, 8, 2, 0), (11, 1, 1, 2)],
    (60, 120) => [(3, 29, 2, 0), (10, 25, 2, 2)],
    (0, 60) => [(3, 29, 1, 0), (10, 25, 1, 2)],
    _ => <(int, int, int, int)>[],
  };
  final sqlite = await openDatabase(inMemoryDatabasePath);
  for (final c in transitions) {
    final wall = DateTime.utc(2026, c.$1, c.$2, c.$3, 30);
    final candidates = sleepWallTimeCandidates(wall);
    check('wall candidates ' + wall.toIso8601String(), candidates.length, c.$4);
    if (candidates.length == 2) {
      check('fold elapsed', candidates.last.difference(candidates.first).inMinutes, 60);
      final record = SleepRecord(start: candidates.first, end: candidates.last,
        source: SleepSource.manual, status: SleepStatus.confirmed);
      final restored = SleepRecord.fromMap(record.toMap());
      check('fold storage round trip', restored.durationMinutes, 60);
      final row = await sqlite.rawQuery(
        'SELECT round((julianday(?) - julianday(?)) * 1440) AS minutes',
        [sleepDateTimeToDb(candidates.last), sleepDateTimeToDb(candidates.first)]);
      check('SQLite fold elapsed', (row.single['minutes'] as num).toInt(), 60);
      final legacy = sleepDateTimeToDb(candidates.last).substring(0, 19);
      final decoded = SleepRecord.fromMap({'start_time': legacy, 'end_time': null,
        'source': 'MANUAL', 'status': 'CONFIRMED'});
      final sqlLegacy = await sqlite.rawQuery(
        "SELECT round((julianday(?, 'utc') - 2440587.5) * 86400000) AS millis", [legacy]);
      (evidence['legacySQLiteObservations'] as List).add({
        'sqliteMillis': sqlLegacy.single['millis'],
        'appMillis': decoded.start.millisecondsSinceEpoch,
        'note': 'Raw SQLite overlap inference is deliberately not used by sleep queries.'});
      final appDb = await DatabaseService.instance.database;
      const testId = -999000;
      try {
        await appDb.insert('sleep_records', {'id': testId, 'start_time': legacy,
          'end_time': sleepDateTimeToDb(candidates.last.add(const Duration(hours: 1))),
          'source': 'MANUAL', 'status': 'CONFIRMED',
          'created_at': DateTime.now().toIso8601String()});
        final included = await DatabaseService.instance.getSleepRecords(
          since: candidates.last.subtract(const Duration(minutes: 1)));
        check('actual DB includes legacy second occurrence',
          included.where((r) => r.id == testId).length, 1);
        final excluded = await DatabaseService.instance.getSleepRecords(
          since: candidates.last.add(const Duration(minutes: 1)));
        check('actual DB excludes legacy before cutoff',
          excluded.where((r) => r.id == testId).length, 0);
      } finally {
        await appDb.delete('sleep_records', where: 'id = ?', whereArgs: [testId]);
      }
    }
    final sleep = SleepRecord(start: DateTime(2026, c.$1, c.$2 - 1, 22),
      end: DateTime(2026, c.$1, c.$2, 6), source: SleepSource.manual, status: SleepStatus.confirmed);
    check('elapsed night ' + c.$1.toString(), sleep.durationMinutes, c.$4 == 0 ? 420 : 540);
    final days = buildSleepDaySlots(records: [sleep], from: DateTime(2026, c.$1, c.$2 - 1),
      to: DateTime(2026, c.$1, c.$2 + 1));
    check('calendar days across transition ' + c.$1.toString(), days.length, 3);
    final analyzer = ShiftPatternAnalyzer(schedule: ShiftSchedule(isRegular: true,
      pattern: const ['Night'], todayIndex: 0, startDate: DateTime(2026, c.$1, c.$2 - 1),
      shiftTypes: const ['Night']), shiftTimes: {'Night': const ShiftTimeRange(
        shiftName: 'Night', startMinutes: 1140, endMinutes: 420)});
    final shift = analyzer.instanceForDate(DateTime(2026, c.$1, c.$2 - 1));
    check('night shift elapsed ' + c.$1.toString(), shift.durationMinutes, c.$4 == 0 ? 660 : 780);
    check('night shift ends at 07:00 ' + c.$1.toString(), shift.end?.hour, 7);
  }
  await sqlite.close();
  if (janOffset == julOffset) {
    check('ordinary clock', sleepWallTimeCandidates(DateTime.utc(2026, 10, 10, 2, 30)).length, 1);
  }
  evidence['errors'] = errors;
  evidence['passed'] = errors.isEmpty;
  evidence['finishedAt'] = DateTime.now().toIso8601String();
  final directory = await getApplicationDocumentsDirectory();
  final file = File(directory.path + '/sleep_device_probe.json');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
  runApp(MaterialApp(home: Scaffold(body: SafeArea(child: Center(child: Text(
    (errors.isEmpty ? 'PASS' : 'FAIL') + '\n43 attribution/average scenarios\n192 × 5 language cases\n' +
    DateTime.now().timeZoneName + '\n' + errors.join('\n'), textAlign: TextAlign.center))))));
}
