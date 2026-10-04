import sys
from usb_audit_device import adb, connect_vm, evaluate, OUT
from usb_audit_scenarios import scenario

adb('shell','am','start','-n','com.hwani1103.shiftbell.dev/com.hwani1103.shiftbell.MainActivity')
connect_vm()
if sys.argv[1]=='prepare':
    scenario('final_schedule_move_notify','providers/date_schedule_provider.dart','''
      final n=DateScheduleNotifier();
      try {
        await n.loadForDate('2031-01-01');
        final result=await n.create(DateSchedule(date:'2030-12-31',content:'OCT03_AUDIT',startMinutes:600,durationMinutes:30,notifyEnabled:true,createdAt:DateTime.now().toIso8601String()));
        check(result.notifyScheduled,'native notification initially scheduled');
        final moved=result.saved.copyWith(date:'2031-01-01',startMinutes:660,notifyOffsetMinutes:10);
        check(await n.update(moved),'native reschedule succeeds');
        check(n.state['2030-12-31']!.isEmpty && n.state['2031-01-01']!.single.id==moved.id,'both date caches updated');
        check((await DatabaseService.instance.getSchedulesForDate('2030-12-31')).isEmpty,'old DB date empty');
        check((await DatabaseService.instance.getSchedulesForDate('2031-01-01')).single.startMinutes==660,'new DB date and time correct');
        check(await n.update(moved.copyWith(notifyEnabled:false)),'notification disabled');
        await n.delete(moved);
        check((await DatabaseService.instance.getSchedulesForDate('2031-01-01')).isEmpty,'deleted');
      } finally {n.dispose();}
    ''')
    scenario('final_ot_boundary','providers/overtime_provider.dart','''
      final n=OvertimeNotifier();try {
        await Future.wait(List.generate(10,(_)=>n.adjust('2030-12-31',30)));
        await n.adjust('2031-01-01',60);
        await n.loadForRange(DateTime(2030,12,31),DateTime(2031,1,1));
        check(n.getMonthTotal(2030,12)==300 && n.getMonthTotal(2031,1)==60,'year boundary totals');
        await DatabaseService.instance.adjustOvertime('2030-12-31',-600);
        await n.loadForRange(DateTime(2030,12,31),DateTime(2031,1,1));
        check(n.getForDate('2030-12-31')==0,'external zero evicts stale cache');
      } finally {n.dispose();}
    ''')
    scenario('final_memo_before_restart','providers/memo_provider.dart','''
      final n=MemoNotifier();try {
        check(await n.createMemo('2031-01-02','OCT03_AUDIT_before'),'create');
        final id=n.getMemosForDate('2031-01-02').single.id!;
        await n.updateMemo(id,'2031-01-02','OCT03_AUDIT_after');
        check(n.getMemosForDate('2031-01-02').single.memoText=='OCT03_AUDIT_after','edited');
      } finally {n.dispose();}
    ''')
    pid=adb('shell','pidof','com.hwani1103.shiftbell.dev').decode().strip()
    adb('shell','run-as','com.hwani1103.shiftbell.dev','kill','-9',pid)
    adb('shell','am','start','-n','com.hwani1103.shiftbell.dev/com.hwani1103.shiftbell.MainActivity')
    print('Dev process restarted; attach compiler then verify.')
else:
    scenario('final_memo_after_restart','providers/memo_provider.dart','''
      final n=MemoNotifier();try {
        await n.loadMemosForDate('2031-01-02');
        final m=n.getMemosForDate('2031-01-02').single;
        check(m.memoText=='OCT03_AUDIT_after','edited value persisted through process kill');
        await n.deleteMemo(m.id!,'2031-01-02');
        check(n.getMemosForDate('2031-01-02').isEmpty,'delete');
      } finally {n.dispose();}
    ''')
    import usb_oct03_restore_baseline
