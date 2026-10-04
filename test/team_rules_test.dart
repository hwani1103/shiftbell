import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shiftbell/models/team_rule.dart';
import 'package:shiftbell/models/team_schedule_config.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/backup_payload.dart';
import 'package:shiftbell/services/backup_validator.dart';
import 'package:shiftbell/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final date = DateTime(2026, 10, 3);
  final rules = {
    'A': TeamRule.cycle(['Day','Day','Off','Off','Night','Night','Off','Off'], date, 0),
    'B': TeamRule.cycle(['Day','Off','Night'], date, 0),
    'C': TeamRule.cycle(['Day','Off','Night','Off'], date, 0),
    'D': TeamRule.cycle(['Day','Day','Day','Off','Off','Off','Night','Night','Night','Off','Off','Off'], date, 0),
    'E': TeamRule.weekly(['Work','Work','Work','Work','Work','Off','Off']),
  };
  TeamScheduleConfig roster() => TeamScheduleConfig(names: rules.keys.toList(),
      offsets: const {}, myTeam: 'A', individual: true, rules: rules).materialize(rules['A']!.shifts);
  ShiftSchedule mainFor(String team, {int? id}) => ShiftSchedule(id: id, isRegular: true,
    pattern: rules[team]!.shifts, todayIndex: rules[team]!.indexOn(date), startDate: date,
    shiftTypes: ['Day','Night','Off','Work','Unused'], activeShiftTypes: rules[team]!.shifts.toSet().toList());

  late Directory temp;
  final service = DatabaseService.instance;
  setUpAll(() async {
    sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('roster_rules_');
    await databaseFactory.setDatabasesPath(temp.path);
    DatabaseService.debugIsAndroidOverride = false;
  });
  tearDownAll(() async {
    await (await service.database).close();
    await temp.delete(recursive: true);
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final db = await service.database;
    await db.delete('team_schedule_config');
    await db.delete('shift_schedule');
    await service.saveShiftSchedule(mainFor('A', id: 1));
  });

  test('independent 8/3/4/12-day rules allow all teams on the same shift', () {
    final config = roster();
    expect(['A','B','C','D'].map((t) => config.rules[t]!.shiftOn(date)), everyElement('Day'));
    expect(config.rules['B']!.shiftOn(DateTime(2026,10,6)), 'Day');
    expect(config.rules['C']!.shiftOn(DateTime(2026,10,6)), 'Off');
    final roundTrip = TeamScheduleConfig.fromJson(jsonDecode(jsonEncode(config.toJson())));
    expect(roundTrip.toJson(), config.toJson());
    for (var d = -400; d <= 400; d++) {
      final day = DateTime(2026,10,3+d);
      for (final team in rules.keys) {
        expect(roundTrip.rules[team]!.shiftOn(day), rules[team]!.shiftOn(day));
      }
    }
  });

  test('weekday conversion stays anchored across years, leap days and DST dates', () {
    final rule = rules['E']!;
    final main = mainFor('E');
    for (var d = -1400; d < 1400; d++) {
      final day = DateTime(2026, 10, 3 + d, 23, 59);
      final expected = day.weekday <= 5 ? 'Work' : 'Off';
      expect(rule.shiftOn(day), expected);
      expect(main.getShiftForDate(day), expected);
    }
  });

  test('legacy offsets migrate without changing any team date', () async {
    SharedPreferences.setMockInitialValues({'all_teams_names':['A','B','C','D'],
      'all_teams_offsets':jsonEncode({'A':0,'B':2,'C':4,'D':6}), 'all_teams_my_team':'A'});
    final old = TeamScheduleConfig.read(await SharedPreferences.getInstance())!;
    final saved = (await service.getTeamScheduleConfig())!;
    expect(saved.individual, false);
    for (final team in old.names) {
      for (var d=-20; d<20; d++) {
        final day = DateTime(2026,10,3+d);
        expect(saved.rules[team]!.indexOn(day), old.indexOn(team,day,8));
      }
    }
    await service.saveTeamScheduleConfig(null);
    expect(await service.getTeamScheduleConfig(), isNull, reason:'stale preferences cannot resurrect roster');
  });

  test('legacy duplicate positions preserve teams as independent rules', () async {
    SharedPreferences.setMockInitialValues({'all_teams_names':['A','B','C','D'],
      'all_teams_offsets':jsonEncode({'A':0,'B':2,'C':4,'D':0}), 'all_teams_my_team':'A'});
    final saved = (await service.getTeamScheduleConfig())!;
    expect(saved.individual, true);
    expect(saved.names, ['A','B','C','D']);
    for (var d=-20; d<20; d++) {
      final day = DateTime(2026,10,3+d);
      expect(saved.rules['A']!.shiftOn(day), saved.rules['D']!.shiftOn(day));
    }
    expect((await service.getTeamScheduleConfig())!.toJson(), saved.toJson());
  });

  test('switch A to E to C keeps every roster rule and can return to A', () async {
    var config = roster();
    await service.saveTeamScheduleConfig(config);
    for (final team in ['E','C','B','D','A']) {
      final before = (await service.getShiftSchedule())!;
      final after = mainFor(team, id: before.id);
      final next = config.withMyTeam(team);
      await service.applyTeamScheduleChange(before: before, after: after, expectedTeams: config, nextTeams: next);
      config = (await service.getTeamScheduleConfig())!;
      expect(config.myTeam, team);
      expect(config.toJson()['teams'], roster().toJson()['teams']);
      expect((await service.getShiftSchedule())!.getShiftForDate(date), rules[team]!.shiftOn(date));
    }
  });

  test('reset commits schedule, roster and alarm settings together', () async {
    await service.saveTeamScheduleConfig(roster());
    final db = await service.database;
    await db.insert('shift_alarm_templates', {'shift_type':'Day','time':'07:30','alarm_type_id':1,'day_offset':0});
    await db.execute("CREATE TRIGGER fail_reset BEFORE INSERT ON team_schedule_config BEGIN SELECT RAISE(ABORT,'test reset failure'); END");
    try {
      await expectLater(service.deleteAllAlarms(resetSchedule:true), throwsA(anything));
      expect(await service.getShiftSchedule(), isNotNull);
      expect(await service.getTeamScheduleConfig(), isNotNull);
      expect(await db.query('shift_alarm_templates'), isNotEmpty);
    } finally {
      await db.execute('DROP TRIGGER fail_reset');
    }
    await service.deleteAllAlarms(resetSchedule:true);
    expect(await service.getShiftSchedule(), isNull);
    expect(await service.getTeamScheduleConfig(), isNull);
    for (final table in ['alarms','shift_alarm_templates','alarm_overrides','alarm_history','alarm_creation_log']) {
      expect(await db.query(table), isEmpty, reason:table);
    }
  });

  test('SQL failure rolls calendar and roster back together', () async {
    final config = roster(); await service.saveTeamScheduleConfig(config);
    final db = await service.database;
    final before = (await service.getShiftSchedule())!;
    await db.execute("CREATE TRIGGER fail_roster BEFORE INSERT ON team_schedule_config BEGIN SELECT RAISE(ABORT,'test failure'); END");
    try {
      await expectLater(service.applyTeamScheduleChange(before:before, after:mainFor('E',id:before.id),
        expectedTeams:config, nextTeams:config.withMyTeam('E')), throwsA(anything));
      expect((await service.getShiftSchedule())!.toMap(), before.toMap());
      expect((await service.getTeamScheduleConfig())!.myTeam, 'A');
    } finally { await db.execute('DROP TRIGGER fail_roster'); }
  });

  test('settings schedule change deletes both basic and individual rosters', () async {
    for (final config in [roster(), TeamScheduleConfig(names:['A','B'], offsets:{'A':rules['A']!.indexOn(TeamScheduleConfig.baseDate),
      'B':(rules['A']!.indexOn(TeamScheduleConfig.baseDate)+2)%8}, myTeam:'A').materialize(rules['A']!.shifts)]) {
      await service.saveShiftSchedule(mainFor('A',id:1));
      await service.saveTeamScheduleConfig(config);
      final before = (await service.getShiftSchedule())!;
      await service.applyTeamScheduleChange(before:before, after:mainFor('A',id:1), expectedTeams:config, nextTeams:null);
      expect(await service.getTeamScheduleConfig(), isNull);
    }
  });

  test('stale editor cannot overwrite a changed roster', () async {
    final config = roster(); await service.saveTeamScheduleConfig(config);
    final before = (await service.getShiftSchedule())!;
    await service.saveTeamScheduleConfig(null);
    await expectLater(service.applyTeamScheduleChange(before:before, after:mainFor('E',id:1),
      expectedTeams:config, nextTeams:config.withMyTeam('E')), throwsStateError);
    expect((await service.getShiftSchedule())!.pattern, before.pattern);
  });

  test('only-other-team shift names are protected; swap rename updates every rule', () async {
    await service.saveTeamScheduleConfig(roster());
    final before = (await service.getShiftSchedule())!;
    expect(await service.referencedShiftNames(before), contains('Work'));
    final changes = {'Work':'Unused','Unused':'Work'};
    final after = ShiftSchedule.fromMap({...before.toMap(), 'shift_types':'Day,Night,Off,Unused,Work'});
    await service.renameShiftAtomic(renamedShifts:changes,newSchedule:after,expectedSchedule:before);
    expect((await service.getTeamScheduleConfig())!.rules['E']!.shifts.first,'Unused');
    final current = (await service.getShiftSchedule())!;
    final deletion = ShiftSchedule.fromMap({...current.toMap(),'shift_types':'Day,Night,Off,Work'});
    await expectLater(service.renameShiftAtomic(renamedShifts:{},newSchedule:deletion,expectedSchedule:current,
      deletedShifts:{'Unused'}),throwsStateError);
  });

  test('backup validates complete rules and rejects broken weekly/name references', () async {
    final db = await service.database;
    final config = roster();
    final tables = <String,List<Map<String,dynamic>>>{
      'alarm_types':await db.query('alarm_types'), 'shift_schedule':await db.query('shift_schedule'),
      'team_schedule_config':[{'id':1,'config':jsonEncode(config.toJson())}],
    };
    Future<List<String>> validate() => BackupValidator.validate(BackupPayload(
      schemaVersion:kBackupSchemaVersion, exportedAt:DateTime.now(), appVersionName:"test",appVersionCode:25,
      tables:tables, preferences:{}), db);
    expect(await validate(), isEmpty);
    final bad = jsonDecode(jsonEncode(config.toJson())) as Map<String,dynamic>;
    (bad['teams'] as List).last['rule']['shifts'] = ['Work'];
    tables['team_schedule_config'] = [{'id':1,'config':jsonEncode(bad)}];
    expect(await validate(), contains('Invalid team roster'));
  });
}
