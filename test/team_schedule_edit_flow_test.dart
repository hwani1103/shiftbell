import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/services/database_service.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/constants/layout_limits.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/team_schedule_config.dart';
import 'package:shiftbell/screens/all_teams_setup_screen.dart';
import 'package:shiftbell/screens/team_schedule_edit_screen.dart';
import 'package:shiftbell/widgets/app_shift_chip.dart';
import 'package:shiftbell/widgets/calendar_header_actions.dart';
import 'package:shiftbell/widgets/team_assignment_grid.dart';

const pattern = ['주간', '주간', '휴무', '휴무', '야간', '야간', '휴무', '휴무'];

Future<void> mount(WidgetTester tester, Widget child,
    {double width = 360}) async {
  tester.view.physicalSize = Size(width, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      child: ScreenUtilInit(
          designSize: const Size(360, 780),
          builder: (context, _) {
            ScreenUtil.configure(
                data: appContentMediaQuery(
                    MediaQueryData.fromView(View.of(context))),
                designSize: const Size(360, 780));
            return MaterialApp(
                locale: const Locale('ko'),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate
                ],
                home: child);
          })));
  await tester.pumpAndSettle();
  if (child is AllTeamsSetupScreen) {
    await tester.runAsync(() async {
      await DatabaseService.instance.saveShiftSchedule(ShiftSchedule(id:1, isRegular:true,
        pattern:child.pattern, todayIndex:child.myTodayIndex, startDate:DateTime.now(),
        shiftTypes:child.pattern.toSet().toList()));
    });
  }
}

void main() {
  late Directory temp;
  setUpAll(() async {
    sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('roster_flow_');
    await databaseFactory.setDatabasesPath(temp.path);
    DatabaseService.debugIsAndroidOverride = false;
  });
  tearDownAll(() async { await (await DatabaseService.instance.database).close(); await temp.delete(recursive:true); });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await (await DatabaseService.instance.database).delete('team_schedule_config');
  });

  for (final count in [2, 3, 4, 5, 6]) {
    testWidgets(
        '$count teams: every roster entry participates in original order',
        (tester) async {
      final names = List.generate(count, (i) => '${i + 1}');
      await mount(
          tester,
          AllTeamsSetupScreen(
              pattern: pattern, myTodayIndex: 4, existingTeamNames: names));
      final myChip = find.byWidgetPredicate(
          (w) => w is AppShiftChip && w.label == names.last && w.onTap != null);
      await tester.ensureVisible(myChip);
      await tester.tap(myChip);
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(find.byKey(
          const ValueKey('team-mode-shared'))).selected, isTrue);
      expect(find.text('다른 조'), findsNothing);
      for (var i = 0; i < count - 1; i++) {
        final chip = find
            .byWidgetPredicate((w) =>
                w is AppShiftChip && w.label == names[i] && w.onTap != null)
            .last;
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await tester.pumpAndSettle();
        final slot =
            find.byKey(ValueKey('team-assign-slot-${i < 4 ? i : i + 1}'));
        await tester.ensureVisible(slot);
        await tester.tap(slot);
        await tester.pumpAndSettle();
      }
      await tester.runAsync(() async {
        await tester.tap(find.text('저장'));
        await Future<void>.delayed(const Duration(milliseconds:100));
      });
      await tester.pumpAndSettle();
      expect(find.text('전체근무표 미리보기'), findsNothing);
      expect(find.byKey(const ValueKey('team-review-save')), findsNothing);
      final saved = (await tester.runAsync(() => DatabaseService.instance.getTeamScheduleConfig()))!;
      expect(saved.names, names);
      expect(saved.myTeam, names.last);
      expect(saved.indexOn(names.last, DateTime.now(), 8), 4);
      expect(saved.offsets.values.toSet().length, count);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'deleting a focused team and changing my team leaves usable assignments',
      (tester) async {
    await mount(
        tester, const AllTeamsSetupScreen(pattern: pattern, myTodayIndex: 4));
    await tester.tap(find.byWidgetPredicate(
        (w) => w is AppShiftChip && w.label == 'C' && w.onTap != null));
    await tester.pumpAndSettle();
    await tester
        .tap(find.text(lookupAppLocalizations(const Locale('ko')).commonEdit));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '나');
    await tester.tap(find.byIcon(Icons.close).at(1));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '라');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();
    await tester.tap(find
        .byWidgetPredicate(
            (w) => w is AppShiftChip && w.label == 'A' && w.onTap != null)
        .first);
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate(
            (w) => w is AppShiftChip && w.label == 'C' && w.onTap != null),
        findsNWidgets(2));
    expect(find.text('나'), findsNothing);
    expect(find.text('라'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'dismissed duplicate names never leak; committed rename keeps the assigned slot',
      (tester) async {
    await mount(
        tester, const AllTeamsSetupScreen(pattern: pattern, myTodayIndex: 4));
    await tester.tap(find.byWidgetPredicate(
        (w) => w is AppShiftChip && w.label == 'C' && w.onTap != null));
    await tester.pumpAndSettle();
    await tester.tap(find
        .byWidgetPredicate(
            (w) => w is AppShiftChip && w.label == 'A' && w.onTap != null)
        .last);
    await tester.pumpAndSettle();
    final slot = find.byKey(const ValueKey('team-assign-slot-0'));
    await tester.ensureVisible(slot);
    await tester.tap(slot);
    await tester.pumpAndSettle();
    final edit =
        find.text(lookupAppLocalizations(const Locale('ko')).commonEdit);
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'B');
    Navigator.of(tester.element(find.byType(TextField).first)).pop();
    await tester.pumpAndSettle();
    expect(find.descendant(of: slot, matching: find.text('A')), findsOneWidget);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'A');
    await tester.enterText(find.byType(TextField).first, '가');
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: slot, matching: find.text('가')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('team-assign-slot-4')),
            matching: find.text('C')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor matches creator cell size and long cycles add rows', (tester) async {
    await mount(tester, const AllTeamsSetupScreen(pattern: pattern, myTodayIndex: 4), width: 360);
    await tester.tap(find.byWidgetPredicate(
      (widget) => widget is AppShiftChip && widget.label == 'C' && widget.onTap != null));
    await tester.pumpAndSettle();
    final creator = tester.getRect(find.byKey(const ValueKey('team-assign-slot-0')));
    final extended = List.generate(32, (index) => pattern[index % pattern.length]);
    const config = TeamScheduleConfig(names: ['A', 'B', 'C', 'D'],
      offsets: {'A': 0, 'B': 8, 'C': 16, 'D': 24}, myTeam: 'C');
    await mount(tester, TeamScheduleEditScreen(teams: config, pattern: extended,
      date: DateTime(2024, 1, 1)), width: 360);
    await tester.tap(find.byKey(const ValueKey('team-edit-switch')));
    await tester.pumpAndSettle();
    final first = tester.getRect(find.byKey(const ValueKey('team-switch-slot-0')));
    final fifth = tester.getRect(find.byKey(const ValueKey('team-switch-slot-4')));
    final sixth = tester.getRect(find.byKey(const ValueKey('team-switch-slot-5')));
    expect(first.width, closeTo(creator.width, 0.01));
    expect(first.height, closeTo(creator.height, 0.01));
    expect(fifth.top, first.top);
    expect(sixth.top, greaterThan(first.bottom));
    await tester.ensureVisible(find.byKey(const ValueKey('team-switch-slot-31')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 412.0, 806.0]) {
    testWidgets(
        'only assigned teams selectable; confirmation cancellation preserves roster $width',
        (tester) async {
      const config = TeamScheduleConfig(
          names: ['A', 'B', 'C', 'D'],
          offsets: {'A': 0, 'B': 2, 'C': 4, 'D': 6},
          myTeam: 'C');
      SharedPreferences.setMockInitialValues({
        'all_teams_names': config.names,
        'all_teams_offsets': jsonEncode(config.offsets),
        'all_teams_my_team': 'C'
      });
      await mount(
          tester,
          TeamScheduleEditScreen(
              teams: config, pattern: pattern, date: DateTime(2024, 1, 1)),
          width: width);
      await tester.tap(find.byKey(const ValueKey('team-edit-switch')));
      await tester.pumpAndSettle();
      for (final i in [1, 3, 4, 5, 7]) {
        final chip = tester.widget<TeamAssignmentChip>(
            find.byKey(ValueKey('team-switch-slot-$i')));
        expect(chip.onTap, isNull);
      }
      await tester.tap(find.byKey(const ValueKey('team-switch-slot-0')));
      await tester.pumpAndSettle();
      expect(find.text('변경하실 조를 선택해주세요.'), findsOneWidget);
      expect(find.text('현재 근무조 (C조)에서 A조로 근무스케줄을 변경합니다.'), findsOneWidget);
      expect(find.byType(TeamAssignmentGrid), findsOneWidget);
      expect(
          tester
              .widget<TeamAssignmentChip>(
                  find.byKey(const ValueKey('team-switch-slot-0')))
              .selected,
          isTrue);
      final mine = find.byKey(const ValueKey('team-switch-slot-4'));
      expect(tester.widget<TeamAssignmentChip>(mine).isMine, isTrue);
      expect(
          find.descendant(of: mine, matching: find.text('5')), findsOneWidget);
      expect(
          find.descendant(of: mine, matching: find.text('C')), findsOneWidget);
      final reset =
          tester.getRect(find.byKey(const ValueKey('team-edit-recreate')));
      expect(reset.bottom, lessThan(tester.getRect(find.text('저장')).top));
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(find.textContaining('고정알람도\nA조'), findsOneWidget);
      await tester.tap(find.text('취소').last);
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(TeamScheduleConfig.read(prefs)!.myTeam, 'C');
      expect(TeamScheduleConfig.read(prefs)!.offsets, config.offsets);
      await tester
          .ensureVisible(find.byKey(const ValueKey('team-edit-recreate')));
      await tester.tap(find.byKey(const ValueKey('team-edit-recreate')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소').last);
      await tester.pumpAndSettle();
      expect(TeamScheduleConfig.read(prefs), isNotNull);
      await tester.tap(find.byKey(const ValueKey('team-edit-recreate')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds:100)); });
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => DatabaseService.instance.getTeamScheduleConfig()), isNull);
      expect(tester.takeException(), isNull);
    });
  }

  for (final editorial in [false, true]) {
    testWidgets(
        'header actions remain one trailing row at 320, editorial=$editorial',
        (tester) async {
      await mount(
          tester,
          Scaffold(
              body: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: CalendarHeaderActions(
                      onToday: () {},
                      onAllShifts: () {},
                      onFriends: () {},

                      isKorean: true,
                      editorial: editorial))),
          width: 320);
      final buttons = find.byType(TextButton);
      expect(buttons, findsNWidgets(3));
      expect(find.byIcon(Icons.alarm_add_rounded), findsNothing);
      expect(find.text('원터치'), findsNothing);
      final first = tester.getRect(buttons.first);
      expect(first.height, greaterThanOrEqualTo(44));
      for (var i = 0; i < 3; i++) {
        final rect = tester.getRect(buttons.at(i));
        expect(rect.top, first.top);
        expect(rect.height, greaterThanOrEqualTo(44));
        final style = tester
            .widget<TextButton>(buttons.at(i))
            .style!
            .textStyle!
            .resolve({})!;
        expect(style.decoration, TextDecoration.none);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
