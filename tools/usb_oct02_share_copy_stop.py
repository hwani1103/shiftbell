import re,xml.etree.ElementTree as ET
from usb_audit_device import adb,evaluate,capture,tap_text,OUT
from usb_audit_scenarios import scenario
adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
root=ET.fromstring(adb('exec-out','cat','/sdcard/usb_audit_ui.xml'))
copies=[n for n in root.iter('node') if (n.get('text') or n.get('content-desc'))=='복사']
assert len(copies)==2,'both copy icons need accessible label'
x,y,r,b=map(int,re.findall(r'\d+',copies[0].get('bounds')))
adb('shell','input','tap',str((x+r)//2),str((y+b)//2))
scenario('share_ui_clipboard','screens/my_share_code_screen.dart',"""
final uid=await FriendSyncService.instance.getOrCreateOwnerId();final clip=await Clipboard.getData('text/plain');
check(clip?.text=='SB2:$uid','actual UI copy contains own code');
check((await FriendSyncService.instance.getShareState()).isActive,'actual UI sharing active');
""")
evaluate('share_stop_offline_prepare','services/friend_sync_service.dart',"(() async {await FirebaseFirestore.instance.disableNetwork();return 'Firestore offline';})()")
tap_text('^공유 중지$');capture('share_stop_confirmation')
