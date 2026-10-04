from usb_audit_scenarios import scenario
scenario('friend_actual_server_aba','services/friend_sync_service.dart',"""
 final s=FriendSyncService.instance;await FirebaseFirestore.instance.enableNetwork();
 final uid=await s.getOrCreateOwnerId();check(uid!=null,'installation owner available');
 final doc=FirebaseFirestore.instance.collection('friend_schedules').doc(uid);
 check(!(await s.getShareState()).isActive,'original sharing off');
 check(!(await doc.get(const GetOptions(source:Source.server))).exists,'no original remote document');
 final initial=ShiftSchedule(isRegular:true,shiftTypes:['AuditDay','AuditNight'],pattern:['AuditDay','AuditNight'],todayIndex:0,startDate:DateTime(2026,10,2),assignedDates:{'2026-10-03':'AuditDay'});
 final changed=ShiftSchedule(isRegular:true,shiftTypes:['AuditDay','AuditNight'],pattern:['AuditNight','AuditDay'],todayIndex:0,startDate:DateTime(2026,10,2),assignedDates:{'2026-10-03':'AuditNight'});
 try{
 check(await s.startSharing(schedule:initial,ownerName:'Oct02 ABA')!=null,'sharing started');
 final generation=(await s.getShareState()).generation;
 for(final fixture in [initial,changed,initial]){
 await s.syncIfEnabled(fixture);
 final remote=(await doc.get(const GetOptions(source:Source.server))).data()!;
 check(jsonEncode(remote['pattern'])==jsonEncode(fixture.pattern),'server pattern matches current A/B/A');
 check((remote['assignedDates'] as Map)['2026-10-03']==fixture.assignedDates!['2026-10-03'],'server date assignment matches current A/B/A');
 final fetched=await s.fetchByOwnerId(uid!);
 check(fetched!=null && fetched!.getShiftForDate(DateTime(2026,10,3))==fixture.assignedDates!['2026-10-03'],'receiver decode sees current assignment');
 check((await s.getShareState()).generation==generation && !(await s.getShareState()).dirty,'same generation and confirmed fingerprint');
 }
 }finally{await s.stopSharing();}
 check(!(await doc.get(const GetOptions(source:Source.server))).exists,'own temporary document deleted');
 """,timeout=150)
