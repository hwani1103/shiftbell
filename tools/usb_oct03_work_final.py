from usb_audit_scenarios import scenario
scenario('final_work_midnight_saved','services/database_service.dart','''
 final service=DatabaseService.instance;final original=(await service.getShiftSchedule())!;
 final names=original.shiftTypes;check(names.isNotEmpty,'existing shifts');
 final first=names.first;
 final saved=await service.saveShiftTimeRange(first,ShiftTimeRange(shiftName:first,startMinutes:1140,endMinutes:420));
 check(saved!.getDurationMinutes(first)==720,'overnight 19-07 duration saved');
 check((await service.getConditionShiftTimes())[first]!.crossesMidnight,'overnight time record saved');
 if(names.length>1){
  final second=names[1];await service.saveShiftTimeRange(second,ShiftTimeRange(shiftName:second,startMinutes:540,endMinutes:1020));
  final latest=await service.saveShiftTimeRange(second,null);
  check(latest!.getDurationMinutes(first)==720 && latest.getDurationMinutes(second)==0,'reset second shift preserves first');
 }
''')
import usb_oct03_restore_baseline
