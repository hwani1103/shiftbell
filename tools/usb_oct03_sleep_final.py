from usb_audit_device import connect_vm
from usb_audit_scenarios import scenario
connect_vm()
scenario('final_sleep_manual_overlap_candidate','providers/sleep_record_provider.dart','''
 final n=SleepRecordNotifier();await n.refresh();
 try {
  final d=DatabaseService.instance;
  final start=DateTime(2031,1,3,23);final end=DateTime(2031,1,4,7);
  await n.addManual(start:start,end:end);
  final manual=n.state.value!.singleWhere((r)=>r.start==start);
  check((await n.findOverlap(start.add(const Duration(hours:1)),end))?.id==manual.id,'manual overlap guard identifies conflict');
  await n.updateTimes(manual,start:start,end:end.subtract(const Duration(hours:1)));
  check(n.state.value!.singleWhere((r)=>r.id==manual.id).end==end.subtract(const Duration(hours:1)),'manual edit');
  final candidateId=await d.insertSleepRecord(SleepRecord(start:start.add(const Duration(hours:1)),end:end,source:SleepSource.autoDetected,status:SleepStatus.pendingConfirmation));
  await n.refresh();final candidate=n.state.value!.singleWhere((r)=>r.id==candidateId);
  check((await n.confirmPending(candidate))?.id==manual.id,'conflicting automatic candidate rejected');
  check(n.state.value!.singleWhere((r)=>r.id==candidateId).status==SleepStatus.pendingConfirmation,'candidate remains pending');
  check(await n.confirmPending(candidate,overrideStart:end,overrideEnd:end.add(const Duration(hours:1)))==null,'nonoverlap candidate confirmed');
  await n.refresh();check(n.state.value!.singleWhere((r)=>r.id==candidateId).status==SleepStatus.confirmed,'confirmation persisted');
  await n.deleteRecord(manual.id!);
  check(!n.state.value!.any((r)=>r.id==manual.id),'manual deleted');
  /* Remove fixture without training rejection history. */
  await d.deleteSleepRecord(candidateId);
 }finally{n.dispose();}
''')
import usb_oct03_restore_baseline
