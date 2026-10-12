import json,sys
from usb_audit_device import evaluate,OUT
from usb_audit_scenarios import scenario
if sys.argv[1]=='prepare':
 scenario('web_fixture_start','services/friend_sync_service.dart',"""
 final s=FriendSyncService.instance;final uid=await s.getOrCreateOwnerId();
 check(!(await s.getShareState()).isActive,'original sharing off');
 check(!(await FirebaseFirestore.instance.collection('friend_schedules').doc(uid).get(const GetOptions(source:Source.server))).exists,'own remote absent');
 check(await s.startSharing(schedule:ShiftSchedule(isRegular:true,shiftTypes:['Day Shift','Night Shift','Day Off'],pattern:['Day Shift','Night Shift','Day Off'],todayIndex:0,startDate:DateTime.now()),ownerName:'Oct02 Web Audit')!=null,'temporary web schedule published');
 """)
 uid=evaluate('export_web_owner','services/friend_sync_service.dart',"(() async {return (await FriendSyncService.instance.getOrCreateOwnerId())!;})()")
 (OUT/'web_config.json').write_text(json.dumps({'url':'https://shiftbell-29f31.web.app/?code=SB2:'+uid}),encoding='utf-8')
elif sys.argv[1]=='colors':
 scenario('web_fixture_colors','services/friend_sync_service.dart',"""
 final s=FriendSyncService.instance;check((await s.getShareState()).isActive,'own web fixture active');
 final colors={'Day Shift':0xFF90CAF9,'Night Shift':0xFFCE93D8,'Day Off':0xFFC8E6C9};
 await s.syncIfEnabled(ShiftSchedule(isRegular:true,shiftTypes:['Day Shift','Night Shift','Day Off'],pattern:['Day Shift','Night Shift','Day Off'],todayIndex:0,startDate:DateTime.now(),shiftColors:colors));
 final uid=await s.getOrCreateOwnerId();
 final remote=(await FirebaseFirestore.instance.collection('friend_schedules').doc(uid).get(const GetOptions(source:Source.server))).data()!;
 check(colors.entries.every((e)=>(remote['shiftColors'] as Map)[e.key]==e.value),'all three explicit colors stored on server');
 final received=await s.fetchByOwnerId(uid!);
 check(received!=null && colors.entries.every((e)=>received!.shiftColors[e.key]==e.value),'all three colors decoded by receiver');
 """)
else:
 scenario('web_fixture_cleanup','services/friend_sync_service.dart',"""
 await FriendSyncService.instance.stopSharing();
 final uid=await FriendSyncService.instance.getOrCreateOwnerId();
 check(!(await FirebaseFirestore.instance.collection('friend_schedules').doc(uid).get(const GetOptions(source:Source.server))).exists,'own web fixture deleted');
 """)
