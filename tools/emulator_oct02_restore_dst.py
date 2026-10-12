import base64,json
from datetime import datetime
from usb_audit_device import SERIAL,adb,evaluate,OUT,compare_os
from usb_audit_scenarios import scenario
assert SERIAL=='emulator-5556'
scenario('emulator_share_guard','services/friend_sync_service.dart',"""
 check(!(await FriendSyncService.instance.getShareState()).isActive,'emulator sharing is off');
 await FirebaseFirestore.instance.disableNetwork();
 """)
adb('shell','cmd','alarm','set-timezone','America/New_York')
adb('shell','cmd','alarm','set-time',str(int(datetime.fromisoformat('2026-11-01T00:10:00-04:00').timestamp()*1000)))
scenario('dst_restore_prepare','providers/alarm_provider.dart',"""
 final n=AlarmNotifier();try{
 await n.deleteAllAlarmsCompletely();
 await n.addAlarm(Alarm(time:'01:04',date:DateTime.fromMillisecondsSinceEpoch(1793509440000),type:'snoozed',alarmTypeId:3));
 }finally{n.dispose();}
 """)
raw=evaluate('export_dst_restore_payload','services/backup_service.dart','(() async {return (await BackupService.instance.exportAll()).encode();})()')
encoded=base64.b64encode(raw.encode()).decode()
scenario('dst_restore_roundtrip','services/restore_coordinator.dart',f"""
 final d=await DatabaseService.instance.database;final before=(await d.query('alarms')).single;
 final payload=BackupPayload.decode(utf8.decode(base64Decode('{encoded}')));
 await RestoreCoordinator.instance.start(payload,overwrite:true);
 final after=(await d.query('alarms')).single;
 check(after['id']==before['id'] && after['type']=='snoozed','snooze ID retained through overwrite');
 check(parseAlarmDate(after['date'] as String).millisecondsSinceEpoch==1793509440000,'first fold instant retained through overwrite');
 check(!await RestoreCoordinator.instance.hasPendingJob(),'restore job complete');
 check(!(await kAlarmChannel.invokeMethod<bool>('restoreIsLocked')??true),'restore gate released');
 """,timeout=120)
assert compare_os('dst_restore_os')
print('PASS real emulator backup overwrite carries first-fold snooze unchanged')
