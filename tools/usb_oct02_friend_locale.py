import sys,time,json,subprocess
from usb_audit_device import evaluate,adb,OUT,PACKAGE,ADB,SERIAL,compare_os,capture,connect_vm
from usb_audit_scenarios import scenario
action=sys.argv[1]
if action=='start':
 scenario('friend_locale_start','services/friend_sync_service.dart',"""
 final s=FriendSyncService.instance;final uid=await s.getOrCreateOwnerId();
 check(uid!=null,'anonymous owner ready');
 check(!(await s.getShareState()).isActive,'original sharing off');
 check(!(await FirebaseFirestore.instance.collection('friend_schedules').doc(uid).get(const GetOptions(source:Source.server))).exists,'no existing shared document overwritten');
 final schedule=ShiftSchedule(isRegular:true,shiftTypes:['Day','Night','Off'],pattern:['Day','Night','Off'],todayIndex:0,startDate:DateTime.now());
 check(await s.startSharing(schedule:schedule,ownerName:'Oct02 audit')!=null,'KO fixture published');
 check(!(await s.getShareState()).dirty,'publication confirmed');
 await FirebaseFirestore.instance.disableNetwork();
 """)
elif action=='en':
 scenario('friend_locale_offline_en','services/friend_sync_service.dart',"""
 check(WidgetsBinding.instance.platformDispatcher.locale.languageCode=='en','actual Android app locale English');
 final s=FriendSyncService.instance;
 await s.onAppResumed(null);
 final state=await s.getShareState();
 check(state.intent==FriendShareIntent.stopPending && !state.isActive && state.dirty,'offline English transition retains stop pending');
 """)
elif action=='online':
 scenario('friend_locale_online_en','services/friend_sync_service.dart',"""
 final s=FriendSyncService.instance;await FirebaseFirestore.instance.enableNetwork();
 await s.onNetworkReconnected(null);
 await FirebaseFirestore.instance.waitForPendingWrites();
 final state=await s.getShareState();check(state.intent==FriendShareIntent.off && !state.dirty,'online confirms shared document removal');
 final uid=await s.getOrCreateOwnerId();
 check(!(await FirebaseFirestore.instance.collection('friend_schedules').doc(uid).get(const GetOptions(source:Source.server))).exists,'own temporary server document absent');
 """)
elif action=='ko':
 scenario('friend_locale_ko_return','services/friend_sync_service.dart',"""
 check(WidgetsBinding.instance.platformDispatcher.locale.languageCode=='ko','actual Android app locale Korean restored');
 final s=FriendSyncService.instance;await s.onAppResumed(null);
 check((await s.getShareState()).intent==FriendShareIntent.off,'return to Korean does not restart sharing');
 """)
else:raise ValueError(action)
