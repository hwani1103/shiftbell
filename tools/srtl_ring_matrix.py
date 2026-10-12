import os
"""Actual OS alarm delivery; visual native UI matrix on the connected SRTL device."""
import time
from srtl_current_audit import fold,locale
from srtl_ring_checks import prepare,dismiss
from usb_audit_device import adb

for lang in ['ko-KR','en-US']:
    locale(lang)
    for opened in [False,True]:
        fold(opened)
        adb('shell','settings','put','system','font_scale',os.environ.get('SRTL_SCALE','1.3'));time.sleep(.5)
        for locked in [False,True]:
            name=lang+('_open_' if opened else '_closed_')+('ring_locked' if locked else 'ring_overlay')
            kind=1 if locked else (2 if opened else 3)
            prepare(name,locked,kind)
            dismiss()
adb('shell','settings','put','system','font_scale','1.0')
print('PASS actual OS delivery and native dismiss for 8 KO/EN fold/lock conditions.',flush=True)
