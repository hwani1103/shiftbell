"""Receiver-side checks against this dev installation's temporary owner document."""
from usb_audit_device import connect_vm, evaluate
from usb_audit_scenarios import scenario

connect_vm()
scenario('r3_friend_start', 'services/friend_sync_service.dart', '''
final s=FriendSyncService.instance;final uid=await s.getOrCreateOwnerId();
check(uid!=null,'anonymous owner ready');
check(!(await FirebaseFirestore.instance.collection('friend_schedules').doc(uid).get(const GetOptions(source:Source.server))).exists,'no existing owner document overwritten');
final now=DateTime.now();
check(await s.startSharing(schedule:ShiftSchedule(isRegular:true,shiftTypes:['Day Shift','Night duty','Day Off'],pattern:['Day Shift','Night duty','Day Off'],todayIndex:0,startDate:now),ownerName:'USB receiver audit')!=null,'temporary owner published');
''')
try:
    scenario('r3_friend_receiver_online', 'providers/friend_provider.dart', '''
final db=await DatabaseService.instance.database;
check((await db.query('friends')).isEmpty,'no original friends changed');
final uid=(await FriendSyncService.instance.getOrCreateOwnerId())!;
final n=FriendNotifier();
try {
 for(final code in ['', 'SB1:abc', 'SB2:', 'SB2:a/b']) {
  check(!await n.addFriend(displayName:'invalid',code:code),'invalid code rejected $code');
 }
 final results=await Future.wait([n.addFriend(displayName:'Receiver',code:'SB2:$uid'),n.addFriend(displayName:'Receiver',code:'SB2:$uid')]);
 check(results.where((r)=>r).length==1,'concurrent same code inserts once');
 check(n.state.length==1 && n.state.single.data!=null,'receiver has server snapshot');
 check(n.state.single.availability==FriendAvailability.available,'online receiver confirmed');
 final first=n.state.single;
 check(!await n.addFriend(displayName:'duplicate',code:'SB2:$uid'),'duplicate rejected');
 final initial=FriendNotifier();
 try {await initial.refreshAll();check(initial.state.single.availability==FriendAvailability.available,'initial DB load completes before automatic refresh');}finally{initial.dispose();}
 await n.refreshAll(force:true);
 final last=n._lastRefreshAllAt;
 await n.refreshAll();check(n._lastRefreshAllAt==last,'automatic refresh throttled');
 await n.refreshAll(force:true);check(n._lastRefreshAllAt!=last,'explicit refresh bypasses throttle');
}finally{n.dispose();}
''')
    evaluate('r3_friend_offline', 'services/friend_sync_service.dart',
             "(() async {await FirebaseFirestore.instance.disableNetwork();return 'network disabled for dev Firestore only';})()")
    scenario('r3_friend_receiver_offline', 'providers/friend_provider.dart', '''
final n=FriendNotifier();
try {
 await n.load();final before=n.state.single;final cache=before.data!.encodeToJsonString();
 check(await n.refreshFriend(before.id,before.ownerId)==FriendRefreshResult.unavailable,'offline is unavailable, not server deletion');
 check(n.state.single.data!.encodeToJsonString()==cache,'cached schedule retained');
 check(n.state.single.availability==FriendAvailability.unconfirmed,'cached receiver visibly unconfirmed');
 check(await n.addFriend(displayName:'Offline audit',code:'SB2:usb_audit_offline_20261001'),'offline new code registered as unconfirmed');
 final added=n.state.firstWhere((e)=>e.ownerId=='usb_audit_offline_20261001');
 check(added.data==null && added.availability==FriendAvailability.unconfirmed,'new offline friend has no fabricated data');
 await n.removeFriend(added.id);
}finally{n.dispose();}
''')
    evaluate('r3_friend_network_restore', 'services/friend_sync_service.dart',
             "(() async {await FirebaseFirestore.instance.enableNetwork();await FriendSyncService.instance.stopSharing();return 'server sharing stopped';})()")
    scenario('r3_friend_receiver_removed', 'providers/friend_provider.dart', '''
final n=FriendNotifier();
try {await n.load();final f=n.state.single;
check(await n.refreshFriend(f.id,f.ownerId)==FriendRefreshResult.serverRemoved,'server notFound removes receiver');
check(n.state.isEmpty,'receiver registration and cache removed');
}finally{n.dispose();}
''')
finally:
    evaluate('r3_friend_cleanup', 'services/friend_sync_service.dart',
             "(() async {await FirebaseFirestore.instance.enableNetwork();await FriendSyncService.instance.stopSharing();await FirebaseFirestore.instance.waitForPendingWrites();final s=await FriendSyncService.instance.getShareState();return 'intent=${s.intent.name};dirty=${s.dirty}';})()")
