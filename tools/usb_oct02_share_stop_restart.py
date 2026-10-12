import time,json
from usb_audit_device import adb,tap_text,capture,evaluate,OUT,PACKAGE,connect_vm
from usb_audit_scenarios import scenario
tap_text('^중지$')
scenario('share_ui_stop_pending','services/friend_sync_service.dart',"""
final s=FriendSyncService.instance;for(var i=0;i<15;i++){if((await s.getShareState()).intent==FriendShareIntent.stopPending)break;await Future<void>.delayed(const Duration(milliseconds:500));}
check((await s.getShareState()).intent==FriendShareIntent.stopPending,'actual UI stop persisted while offline');
""")
time.sleep(5);capture('share_ui_stop_pending_banner')
before=adb('shell','pidof',PACKAGE).decode().strip()
adb('shell','input','keyevent','KEYCODE_HOME');time.sleep(1);adb('shell','am','kill',PACKAGE)
time.sleep(1)
try:remaining=adb('shell','pidof',PACKAGE).decode().strip()
except Exception:remaining=''
assert remaining!=before,'background process did not exit; do not call this cold restart'
(OUT/'share_stop_restart_process.json').write_text(json.dumps({'before_pid':before,'after_kill_pid':remaining}),encoding='utf-8')
adb('shell','am','start','-W','-n',PACKAGE+'/com.hwani1103.shiftbell.MainActivity')
time.sleep(3)
capture('share_stop_restart_online')
print('Cold restart performed; attach then verify server deletion without manually retrying')
