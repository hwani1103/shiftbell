import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shiftbell/constants/platform_channel.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/models/team_schedule_config.dart';
import 'package:shiftbell/providers/schedule_provider.dart';
import 'package:shiftbell/services/database_service.dart';
import 'package:shiftbell/utils/apply_schedule_change.dart';
import 'package:shiftbell/widgets/schedule_change_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('team_change_');
    await databaseFactory.setDatabasesPath(directory.path);
    DatabaseService.debugIsAndroidOverride = false;
  });
  tearDownAll(() async {
    await (await DatabaseService.instance.database).close();
    await directory.delete(recursive: true);
  });

  testWidgets(
      'C to A saves main calendar before native alarm refresh and preserves every team position',
      (tester) async {
    const pattern = ['주간', '주간', '휴무', '휴무', '야간', '야간', '휴무', '휴무'];
    const config = TeamScheduleConfig(
        names: ['A', 'B', 'C', 'D'],
        offsets: {'A': 0, 'B': 2, 'C': 4, 'D': 6},
        myTeam: 'C');
    final date = DateTime(2026, 10, 3);
    SharedPreferences.setMockInitialValues({
      'all_teams_names': config.names,
      'all_teams_offsets': jsonEncode(config.offsets),
      'all_teams_my_team': config.myTeam
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await DatabaseService.instance.saveShiftSchedule(ShiftSchedule(
          isRegular: true,
          pattern: pattern,
          todayIndex: config.indexOn('C', date, 8),
          startDate: date,
          shiftTypes: const ['주간', '야간', '휴무'],
          assignedDates: const {'2026-10-04': '휴무'},
          customShiftColors: const {'주간': 0xff123456},
          shiftDurations: const {'주간': 480}));
      await container.read(scheduleProvider.notifier).refresh();
    });
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kAlarmChannel, (call) async {
      calls.add(call.method);
      if (call.method == 'forceNativeRefreshAndWait') {
        final schedule = (await DatabaseService.instance.getShiftSchedule())!;
        expect(schedule.todayIndex, config.indexOn('A', date, 8));
        expect(
            (await DatabaseService.instance.getTeamScheduleConfig())!
                .myTeam,
            'A');
        return true;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kAlarmChannel, null));
    late WidgetRef ref;
    late BuildContext context;
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            locale: const Locale('ko'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(builder: (c, r, _) {
              ref = r;
              context = c;
              return const Scaffold(body: SizedBox());
            }))));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      expect(
          await applyScheduleChange(
              context,
              ref,
              ScheduleChangeSelection(config.indexOn('A', date, 8), 'A'),
              date,
              config),
          isTrue);
    });
    await tester.pumpAndSettle();
    final saved = container.read(scheduleProvider).value!;
    expect(saved.assignedDates, isEmpty);
    expect(saved.customShiftColors, {'주간': 0xff123456});
    expect(saved.shiftDurations, {'주간': 480});
    final savedTeams = (await tester.runAsync(() => DatabaseService.instance.getTeamScheduleConfig()))!;
    expect(savedTeams.offsets, config.offsets);
    expect(savedTeams.names, config.names);
    expect(calls.where((c) => c == 'forceNativeRefreshAndWait').length, 1);
    expect(calls.indexOf('triggerGuardCheck'),
        greaterThan(calls.indexOf('forceNativeRefreshAndWait')));
    for (var day = -12; day <= 12; day++) {
      final d = date.add(Duration(days: day));
      expect(saved.getShiftForDate(d), pattern[config.indexOn('A', d, 8)]);
    }
    expect(tester.takeException(), isNull);
  });
}
