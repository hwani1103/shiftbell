import sys,xml.etree.ElementTree as ET
from usb_audit_device import adb,tap_text,capture,OUT
action=sys.argv[1]
if action=='tap':tap_text(sys.argv[2])
elif action=='capture':capture(sys.argv[2])
elif action=='texts':
 adb('shell','uiautomator','dump','/sdcard/usb_audit_ui.xml')
 root=ET.fromstring(adb('exec-out','cat','/sdcard/usb_audit_ui.xml'))
 for n in root.iter('node'):
  label=n.get('text') or n.get('content-desc')
  if label:print(repr(label),n.get('bounds'),n.get('enabled'))
else:raise ValueError(action)
