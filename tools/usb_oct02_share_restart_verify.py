from usb_audit_device import connect_vm,evaluate,compare_os
from usb_audit_scenarios import scenario
connect_vm()
scenario('share_stop_cold_restart_completed','services/friend_sync_service.dart',"""
final s=FriendSyncService.instance;final state=await s.getShareState();
check(state.intent==FriendShareIntent.off && !state.dirty,'cold startup automatically completed pending stop');
final uid=await s.getOrCreateOwnerId();
check(!(await FirebaseFirestore.instance.collection('friend_schedules').doc(uid).get(const GetOptions(source:Source.server))).exists,'server confirms own shared document absent');
""")
assert compare_os('share_stop_restart_original_alarm_os')
evaluate('audit_semantics_after_cold','main.dart',"(() {WidgetsBinding.instance.ensureSemantics();return 'semantics retained for UI audit';})()",wait=False)
