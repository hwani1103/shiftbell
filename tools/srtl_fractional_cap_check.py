"""Actual fractional app scales plus a native upper-bound smoke check."""
import os,time
from usb_audit_device import adb,connect_vm
from srtl_current_audit import fold,locale,tab,inspect
from srtl_ring_checks import prepare,dismiss
connect_vm();locale('en-US');fold(False);tab(2)
for scale in ['1.09','1.25','1.28','1.6']:
 adb('shell','settings','put','system','font_scale',scale);time.sleep(.6)
 inspect('en_closed_fractional_'+scale)
for locked in [False,True]:
 prepare('en_closed_native_cap_1.6_'+('locked' if locked else 'overlay'),locked,3)
 dismiss()
adb('shell','settings','put','system','font_scale','1.0')
print('Fractional app scale metrics captured; native 1.6 screenshots require comparison to capped 1.3 UI.',flush=True)
