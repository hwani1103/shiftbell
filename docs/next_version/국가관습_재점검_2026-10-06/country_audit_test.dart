// Research probe only. No layout assertions or production changes.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/l10n/release_locale.dart';
import 'package:shiftbell/l10n/generated/app_localizations.dart';
import 'package:shiftbell/models/friend_schedule.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/widgets/friend_web_calendar.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:shiftbell/services/work_hours_calculator.dart';
import 'package:shiftbell/utils/alarm_wall_time.dart';
import 'package:shiftbell/utils/holiday_util.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  testWidgets('observe public web weekday language and first day', (tester) async {
    // Fixed harness only: no geometry, font, clipping or screenshot assertions.
    tester.view.physicalSize=const Size(800,800);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for(final locale in [const Locale('en','GB'),const Locale('de','DE'),const Locale('pt','BR'),const Locale('hi','IN')]) {
      await tester.pumpWidget(MaterialApp(locale:locale,supportedLocales:releaseSupportedLocales,
        localizationsDelegates:const [AppLocalizations.delegate,GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,GlobalCupertinoLocalizations.delegate],
        home:Scaffold(body:FriendWebCalendar(friendName:'Sample',
          data:FriendScheduleData(ownerName:'Sample',isRegular:false,shiftColors:const {},
            assignedDates:const {},updatedAt:DateTime(2026,10,6)),initialDay:DateTime(2026,10,6),
          showPwaAddressBarHint:false,showQuickInstallButton:false,showInstallPrompt:false))));
      await tester.pumpAndSettle();
      final calendar=tester.widget<TableCalendar>(find.byType(TableCalendar));
      print('WEB_OBSERVED ${jsonEncode({'app':locale.toString(),'calendarLocale':calendar.locale,
        'firstDay':calendar.startingDayOfWeek.name,'englishMondayVisible':find.text('Mon').evaluate().isNotEmpty})}');
      // Current defect characterization. This is not the desired acceptance criterion.
      expect(calendar.locale,'en_US');
      expect(find.text('Mon'),findsOneWidget);
    }
  });
  test('observe eight countries regional defaults without rendering', () async {
    for (final tag in ['en_US','en_GB','en_ZA','en_PH','en_AE','de_DE','pt_BR','hi_IN','en_IN','ar_AE','af_ZA','fil_PH']) {
      final parts = tag.split('_');
      final selected = resolveReleaseLocale([Locale(parts[0],parts[1])], releaseSupportedLocales);
      final material = await GlobalMaterialLocalizations.delegate.load(selected);
      print('REGION ${jsonEncode({'device':tag,'resolved':selected.toString(),
        'firstDay':material.firstDayOfWeekIndex,
        'date':material.formatCompactDate(DateTime(2026,4,5)),
        'delegateTimeDefault':material.formatTimeOfDay(const TimeOfDay(hour:13,minute:5)),
        'delegateTime24':material.formatTimeOfDay(const TimeOfDay(hour:13,minute:5),alwaysUse24HourFormat:true)})}');
      expect(getHolidayName(DateTime(2026,10,9),isKorean:selected.languageCode=='ko'),isNull);
    }
  });
  test('eight countries wall-clock resolver offsets and DST boundaries', () {
    final cases = [
      ['America/New_York','2026-03-08T02:30:00','2026-03-08T07:30:00Z'],
      ['America/New_York','2026-11-01T01:30:00','2026-11-01T06:30:00Z'],
      ['America/Phoenix','2026-07-01T09:00:00','2026-07-01T16:00:00Z'],
      ['Pacific/Honolulu','2026-07-01T09:00:00','2026-07-01T19:00:00Z'],
      ['Europe/London','2026-03-29T01:30:00','2026-03-29T01:30:00Z'],
      ['Europe/London','2026-10-25T01:30:00','2026-10-25T01:30:00Z'],
      ['Europe/Berlin','2026-03-29T02:30:00','2026-03-29T01:30:00Z'],
      ['Europe/Berlin','2026-10-25T02:30:00','2026-10-25T01:30:00Z'],
      ['Africa/Johannesburg','2026-07-01T09:00:00','2026-07-01T07:00:00Z'],
      ['Asia/Manila','2026-07-01T09:00:00','2026-07-01T01:00:00Z'],
      ['Asia/Dubai','2026-07-01T09:00:00','2026-07-01T05:00:00Z'],
      ['America/Sao_Paulo','2026-07-01T09:00:00','2026-07-01T12:00:00Z'],
      ['America/Rio_Branco','2026-07-01T09:00:00','2026-07-01T14:00:00Z'],
      ['America/Noronha','2026-07-01T09:00:00','2026-07-01T11:00:00Z'],
      ['Asia/Kolkata','2026-07-01T09:00:00','2026-07-01T03:30:00Z'],
    ];
    for (final c in cases) {
      final zone = tz.getLocation(c[0]);
      final actual = resolveAlarmWallTime(DateTime.parse('${c[1]}Z'),
        localFromEpoch:(epoch)=>tz.TZDateTime.fromMillisecondsSinceEpoch(zone,epoch));
      expect(actual.toUtc(),DateTime.parse(c[2]),reason:c.join(' '));
    }
    print('WALL_CASES_PASS ${cases.length}');
  });
  test('observe real weekly summary across DST using zoned DateTime inputs', () {
    final observations = <Map<String,Object>>[];
    for (final row in [
      ('Europe/Berlin',3,28,30), ('Europe/Berlin',10,24,26),
      ('Europe/London',3,28,30), ('Europe/London',10,24,26),
      ('America/New_York',3,7,9), ('America/New_York',10,31,33),
    ]) {
      final zone=tz.getLocation(row.$1);
      final start=tz.TZDateTime(zone,2026,row.$2,row.$3);
      final end=tz.TZDateTime(zone,2026,row.$2,row.$4);
      final assignments=<String,String>{};
      final ot=<String,int>{};
      for(var i=0;i<3;i++) {
        final d=tz.TZDateTime(zone,2026,row.$2,row.$3+i);
        assignments[dateKey(d)]='Day';
        ot[dateKey(d)]=(i+1)*10;
      }
      final schedule=ShiftSchedule(isRegular:false,shiftTypes:const ['Day'],
        assignedDates:assignments,shiftDurations:const {'Day':480});
      final result=computeWeekSummary(schedule:schedule,weekStart:start,weekEnd:end,otByDate:ot);
      observations.add({'zone':row.$1,'start':start.toString(),'end':end.toString(),
        'expectedDays':3,'observedDays':result.shiftDayCounts['Day']??0,
        'expectedMinutes':1500,'observedMinutes':result.totalMinutes});
    }
    print('DST_SUMMARY_OBSERVATIONS ${jsonEncode(observations)}');
    // Probe proves a current defect, not a pass against desired behavior.
    expect(observations.any((r)=>r['expectedMinutes']!=r['observedMinutes']),isTrue);
  });
}
