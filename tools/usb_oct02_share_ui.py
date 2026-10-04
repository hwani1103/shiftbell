import re,time,xml.etree.ElementTree as ET
from usb_audit_device import adb,tap_text,capture,evaluate,OUT
from usb_audit_scenarios import scenario
scenario('share_ui_preflight','services/friend_sync_service.dart',"""
final s=FriendSyncService.instance;final uid=await s.getOrCreateOwnerId();
check(!(await s.getShareState()).isActive,'original sharing off');
check(!(await FirebaseFirestore.instance.collection('friend_schedules').doc(uid).get(const GetOptions(source:Source.server))).exists,'no prior shared document overwritten');
""")
adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
root=ET.fromstring(adb('exec-out','cat','/sdcard/usb_audit_ui.xml'))
field=next(n for n in root.iter('node') if n.get('class')=='android.widget.EditText')
x,y,r,b=map(int,re.findall(r'\d+',field.get('bounds')))
adb('shell','input','tap',str((x+r)//2),str((y+b)//2));adb('shell','input','text','Oct02Share');adb('shell','input','keyevent','KEYCODE_BACK')
tap_text('^공유 시작하기$');time.sleep(1);capture('share_ui_started')
tap_text('코드 복사')
scenario('share_ui_clipboard','screens/my_share_code_screen.dart',"""
final uid=await FriendSyncService.instance.getOrCreateOwnerId();
final clip=await Clipboard.getData('text/plain');
if(clip?.text!='SB2:$uid')throw StateError('copied code mismatch');
check((await FriendSyncService.instance.getShareState()).isActive,'actual UI sharing active and own code copied');
""")
