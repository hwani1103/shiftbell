"""Non-destructive resume snapshot before updating the dev application."""
from pathlib import Path
import subprocess, json, hashlib, datetime
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/usb_audit_2026-10-02'
OUT.mkdir(parents=True,exist_ok=True)
ADB='C:/Users/Administrator/AppData/Local/Android/sdk/platform-tools/adb.exe'
PKG='com.hwani1103.shiftbell.dev'
def adb(*args):
    return subprocess.run([ADB,'-s','R5KL20DHWAE',*args],capture_output=True,check=True,timeout=120).stdout
for area in ['user_de','user']:
    blob=adb('exec-out','run-as',PKG,'tar','-cf','-','-C',f'/data/{area}/0/{PKG}','.')
    path=OUT/f'before_resume_{area}.tar'
    if path.exists(): raise RuntimeError('Original snapshot already exists; refusing overwrite')
    path.write_bytes(blob)
(OUT/'before_resume.png').write_bytes(adb('exec-out','screencap','-p'))
(OUT/'before_resume_package.txt').write_bytes(adb('shell','dumpsys','package',PKG))
(OUT/'before_resume_power.txt').write_bytes(adb('shell','dumpsys','power'))
apk=ROOT/'build/app/outputs/flutter-apk/app-dev-debug.apk'
print(json.dumps({'snapshot':'saved','apk_sha256':hashlib.sha256(apk.read_bytes()).hexdigest()},ensure_ascii=False))
