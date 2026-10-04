import sys,json,time
from usb_audit_device import evaluate,adb,tap_text,capture,OUT
from usb_audit_scenarios import scenario
stage=sys.argv[1]
if stage=='prepare':
 scenario('friend_payload_ui_start','services/friend_sync_service.dart',"""
 final s=FriendSyncService.instance;final uid=await s.getOrCreateOwnerId();
 check(!(await FirebaseFirestore.instance.collection('friend_schedules').doc(uid).get(const GetOptions(source:Source.server))).exists,'own remote fixture absent');
 check(await s.startSharing(schedule:ShiftSchedule(isRegular:true,shiftTypes:['AuditDay','AuditNight'],pattern:['AuditDay','AuditNight'],todayIndex:0,startDate:DateTime.now()),ownerName:'Oct02Payload')!=null,'own valid remote fixture published');
 final data=(await FirebaseFirestore.instance.collection('friend_schedules').doc(uid).get(const GetOptions(source:Source.server))).data()!;
 check(data.keys.toSet().difference({'ownerName','isRegular','pattern','todayIndex','startDate','shiftColors','assignedDates','generation','revoked','updatedAt'}).isEmpty,'exact server payload excludes all unrelated private fields');
 """)
 scenario('friend_payload_ui_receiver','providers/friend_provider.dart',"""
 final d=await DatabaseService.instance.database;check((await d.query('friends')).isEmpty,'no original friends');
 final uid=await FriendSyncService.instance.getOrCreateOwnerId();final n=FriendNotifier();try{check(await n.addFriend(displayName:'Oct02Payload',code:'SB2:$uid'),'valid remote fixture cached');}finally{n.dispose();}
 """)
elif stage=='invalid':
 evaluate('friend_payload_ui_corrupt','services/friend_sync_service.dart',"(() async {final uid=await FriendSyncService.instance.getOrCreateOwnerId();await FirebaseFirestore.instance.collection('friend_schedules').doc(uid).update({'assignedDates':{'2026-10-03':123}});return 'only own temporary fixture corrupted';})()")
 adb('shell','input','swipe','540','1020','540','1740','550');time.sleep(2);capture('friend_payload_ui_invalid')
 text=(OUT/'friend_payload_ui_invalid.xml').read_text(encoding='utf-8');assert 'Oct02Payload' in text
 print('invalid UI captured for inspection')
elif stage=='recover':
 evaluate('friend_payload_ui_repair','services/friend_sync_service.dart',"(() async {final uid=await FriendSyncService.instance.getOrCreateOwnerId();await FirebaseFirestore.instance.collection('friend_schedules').doc(uid).update({'assignedDates':<String,String>{}});return 'own fixture repaired';})()")
 adb('shell','input','swipe','540','1020','540','1740','550');time.sleep(2);capture('friend_payload_ui_recovered')
elif stage=='cleanup':
 evaluate('friend_payload_ui_stop','services/friend_sync_service.dart',"(() async {await FriendSyncService.instance.stopSharing();return 'own fixture sharing stopped';})()")
 adb('shell','input','swipe','540','1020','540','1740','550');time.sleep(2);capture('friend_payload_ui_removed')
 scenario('friend_payload_ui_final','providers/friend_provider.dart',"final d=await DatabaseService.instance.database;check((await d.query('friends')).isEmpty,'server removal clears receiver registration');")
else:raise ValueError(stage)
