// Differential regression against the exact pre-change calculator (imports only
// adapted). Run on the unchanged Korea host; never changes the machine timezone.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/models/shift_schedule.dart';
import 'package:shiftbell/providers/work_hours_settings_provider.dart';
import 'package:shiftbell/services/work_hours_calculator.dart' as current;
import 'work_hours_before_reference.dart' as before;

void main() {
  test('Korea old/new month, weekly, payday, manual and implied OT parity', () {
    expect(DateTime(2026,1,1).timeZoneOffset,const Duration(hours:9));
    expect(DateTime(2026,7,1).timeZoneOffset,const Duration(hours:9));
    var cases=0;
    for(final year in [2024,2026,2027,2028]) {
      for(var month=1;month<=12;month++) {
        final focused=DateTime(year,month);
        final periods=[const WorkHoursSettings(),
          for(final day in [1,20,28,29,30,31])
            for(final anchor in PaydayCutoffAnchor.values)
              WorkHoursSettings(periodMode:MonthlyPeriodMode.payday,paydayCutoffDay:day,cutoffAnchor:anchor)];
        final oldWeeks=before.weeksCoveringMonth(focused);
        final newWeeks=current.weeksCoveringMonth(focused);
        expect(newWeeks.map((w)=>[w.start.toIso8601String(),w.end.toIso8601String()]),
          oldWeeks.map((w)=>[w.start.toIso8601String(),w.end.toIso8601String()]));
        for(final regular in [true,false]) {
          final assignments=<String,String>{}; final ot=<String,int>{};
          for(var i=-40;i<45;i++) {
            final d=DateTime(year,month,1+i); final key=current.dateKey(d);
            if(!regular || i%3==0) assignments[key]=['Night','Off','Short','Day'][i%4];
            if(i%5!=0) ot[key]=(i%3)*30;
          }
          final schedule=ShiftSchedule(isRegular:regular,shiftTypes:const ['Day','Night','Off','Short'],
            pattern:regular?const ['Day','Day','Night','Off']:null,
            todayIndex:regular?2:null,startDate:regular?DateTime(year,month,1):null,
            assignedDates:assignments,shiftDurations:const {'Day':480,'Night':720,'Off':0,'Short':240});
          final snapshot=jsonEncode(schedule.toMap()); final otSnapshot=jsonEncode(ot);
          for(final range in [...periods.map((s)=>s.periodForMonth(focused)),...oldWeeks]) {
            final a=range.start,b=range.end;
            expect(current.computeTotalWorkMinutes(schedule:schedule,start:a,end:b,otByDate:ot),
              before.computeTotalWorkMinutes(schedule:schedule,start:a,end:b,otByDate:ot));
            final old=before.computeWeekSummary(schedule:schedule,weekStart:a,weekEnd:b,otByDate:ot);
            final now=current.computeWeekSummary(schedule:schedule,weekStart:a,weekEnd:b,otByDate:ot);
            expect(now.shiftDayCounts,old.shiftDayCounts);
            expect(now.shiftMinutes,old.shiftMinutes); expect(now.otMinutes,old.otMinutes);
            for(final enabled in [false,true]) {
              final oldEntries=before.computeOtDisplayEntries(schedule:schedule,start:a,end:b,manualOtByDate:ot,countShiftChangeAsOt:enabled);
              final newEntries=current.computeOtDisplayEntries(schedule:schedule,start:a,end:b,manualOtByDate:ot,countShiftChangeAsOt:enabled);
              expect(newEntries.map((e)=>[e.date.toIso8601String(),e.manualMinutes,e.impliedMinutes,e.fromShift,e.toShift]),
                oldEntries.map((e)=>[e.date.toIso8601String(),e.manualMinutes,e.impliedMinutes,e.fromShift,e.toShift]));
              expect(current.computeOtDisplayTotal(newEntries),before.computeOtDisplayTotal(oldEntries));
              cases++;
            }
          }
          expect(jsonEncode(schedule.toMap()),snapshot);
          expect(jsonEncode(ot),otSnapshot);
        }
      }
    }
    print('KOREA_OLD_NEW_PARITY_CASES=$cases');
  });
}
