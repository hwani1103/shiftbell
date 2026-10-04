"""Capture dev app locale screen without changing app data."""
import sys
from usb_audit_device import OUT, adb

name = sys.argv[1]
(OUT / (name + '.png')).write_bytes(adb('exec-out', 'screencap', '-p'))
print('saved', name)
