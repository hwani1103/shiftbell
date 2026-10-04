from usb_audit_scenarios import scenario
scenario('friend_cache_actual_server','providers/friend_provider.dart',"""
 final d=await DatabaseService.instance.database;
 check((await d.query('friends')).isEmpty,'original friend list empty');
 final s=FriendSyncService.instance;check(!(await s.getShareState()).isActive,'original sharing off');
 final schedule=(await DatabaseService.instance.getShiftSchedule())!;
 final first=schedule.shiftTypes.first;final second=schedule.shiftTypes.firstWhere((x)=>x!=first);
 schedule.assignedDates={'2030-01-01':first};
 final n=FriendNotifier();
 try{
 final uid=await s.startSharing(schedule:schedule,ownerName:'Oct02Cache');
 check(uid!=null,'own fixture published');
 check(await n.addFriend(displayName:'Oct02Cache',code:'SB2:$uid'),'own fixture added');
 await n.refreshAll(force:true);
 final before=(await d.query('friends')).single['data_json'];
 schedule.assignedDates={'2030-01-01':second};await s.syncIfEnabled(schedule);
 check((await s.fetchByOwnerId(uid!))!.assignedDates['2030-01-01']==second,'server has changed assignment');
 await n.refreshAll();
 check((await d.query('friends')).single['data_json']==before,'within two minutes automatic refresh retains cached result');
 await n.refreshAll(force:true);
 final after=FriendScheduleData.decodeFromJsonString((await d.query('friends')).single['data_json'] as String);
 check(after.assignedDates['2030-01-01']==second,'manual force refresh bypasses throttle');
 }finally{
 await s.stopSharing();
 for(final row in await d.query('friends',where:'name=?',whereArgs:['Oct02Cache'])){await n.removeFriend(row['id'] as int);}
 n.dispose();
 }
 check((await d.query('friends')).isEmpty,'original empty friend list restored');
 """,timeout=150)
