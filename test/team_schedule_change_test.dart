import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiftbell/constants/layout_limits.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/team_schedule_config.dart';
import 'package:shiftbell/widgets/schedule_change_dialog.dart';
import 'package:shiftbell/widgets/shift_label_layout.dart';
import 'package:shiftbell/widgets/team_label.dart';

void main() {
  const config = TeamScheduleConfig(
      names: ['A', 'B', 'C', 'D'],
      offsets: {'A': 0, 'B': 1, 'C': 2, 'D': 4},
      myTeam: 'C');
  final date = DateTime(2024, 1, 1);
  const pattern = [
    'Day',
    'Day',
    'Night',
    'Night',
    'Off',
    'Off',
    'Extra',
    'Extra'
  ];

  test('both languages use exactly the same two cell presets', () {
    const style = TextStyle(fontSize: 13, height: 1.15);
    for (final scale in [1.0, 2.0]) {
      ShiftCellMetrics metrics(String s) =>
          ShiftCellMetrics.forNames([s], style, TextScaler.linear(scale));
      final small = metrics('주간');
      final large = metrics('주간근무');
      expect(metrics('A').width, small.width);
      expect(metrics('A').height, small.height);
      for (final label in ['Night Duty', 'WWWWWWWWWW', '특별연장근무']) {
        expect(metrics(label).width, large.width);
        expect(metrics(label).height, large.height);
      }
    }
  });
  test('team matching uses cycle positions, including date progression', () {
    expect(config.teamsAt(0, date, 8), ['A']);
    expect(
        config.teamsAt(1, date, 8), ['B']); // same shift name, different team
    expect(config.teamsAt(3, date, 8), isEmpty);
    expect(config.teamsAt(3, date.add(const Duration(days: 1)), 8), ['C']);
    expect(config.teamsAt(2, date.add(const Duration(days: 8)), 8), ['C']);
  });
  test('matching keeps all positions, unmatched removes only team settings',
      () async {
    SharedPreferences.setMockInitialValues({
      'all_teams_names': config.names,
      'all_teams_offsets': jsonEncode({'A': '0', 'B': '1', 'C': '2', 'D': '4'}),
      'all_teams_my_team': 'C',
      'unrelated': 'keep'
    });
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString('all_teams_offsets');
    expect(TeamScheduleConfig.read(prefs)!.teamsAt(0, date, 8), ['A']);
    await TeamScheduleConfig.applySelection(prefs, 'A');
    expect(TeamScheduleConfig.read(prefs)!.myTeam, 'A');
    expect(prefs.getString('all_teams_offsets'), before);
    expect(prefs.getStringList('all_teams_names'), config.names);
    await TeamScheduleConfig.applySelection(prefs, null);
    expect(TeamScheduleConfig.read(prefs), isNull);
    expect(prefs.getKeys(), {'unrelated'});
  });

  for (final locale in [const Locale('ko'), const Locale('en')]) {
    for (final size in [const Size(320, 568), const Size(806, 895)]) {
      for (final matched in [true, false]) {
        testWidgets('schedule change $locale $size match=$matched',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          ScheduleChangeSelection? result;
          await tester.pumpWidget(ScreenUtilInit(
              designSize: const Size(360, 780),
              builder: (context, _) {
                ScreenUtil.configure(
                    data: appContentMediaQuery(
                        MediaQueryData.fromView(View.of(context))),
                    designSize: const Size(360, 780));
                return MaterialApp(
                  locale: locale,
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates: const [
                    AppLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate
                  ],
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: const TextScaler.linear(2)),
                      child: child!),
                  home: Builder(
                      builder: (context) => Scaffold(
                          body: TextButton(
                              child: const Text('open'),
                              onPressed: () async {
                                result =
                                    await showDialog<ScheduleChangeSelection>(
                                        context: context,
                                        builder: (_) => ScheduleChangeDialog(
                                            pattern: pattern,
                                            date: date,
                                            teams: config));
                              }))),
                );
              }));
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          expect(
              tester
                  .widgetList<TeamLabel>(find.byType(TeamLabel))
                  .where((w) => w.isMine)
                  .every((w) => w.name == 'C'),
              isTrue);
          final slot = find.byKey(ValueKey('schedule-slot-${matched ? 0 : 3}'));
          await tester.ensureVisible(slot);
          await tester.tap(slot);
          await tester.pumpAndSettle();
          final l = lookupAppLocalizations(locale);
          await tester.ensureVisible(find.text(l.commonSave));
          await tester.tap(find.text(l.commonSave));
          await tester.pumpAndSettle();
          if (true) {
            expect(find.text(l.teamScheduleResetConfirm), findsNWidgets(2));
            expect(result, isNull);
            await tester.tap(find.text(l.commonCancel).last);
            await tester.pumpAndSettle();
            expect(find.byType(ScheduleChangeDialog), findsOneWidget);
            expect(result, isNull);
            await tester.tap(find.text(l.commonSave));
            await tester.pumpAndSettle();
            await tester.tap(find.text(l.commonOk));
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          expect(result!.index, matched ? 0 : 3);
          expect(result!.team, isNull);
        });
      }
    }
  }
}
