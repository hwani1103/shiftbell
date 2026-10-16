"""Verify packaged sources and unchanged ShiftBell files after isolated builds."""
from pathlib import Path
import hashlib,json,zipfile,shutil
R=Path(__file__).resolve().parents[3];E=R/'docs/next_version_27이후/game_implementation_v11';L=R/'examples/sync_path_lab'
def sha(data):return hashlib.sha256(data).hexdigest()
def write(name,data):(E/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n','utf-8')
baseline=json.loads((E/'protected_baseline.json').read_text('utf-8'))
assert json.loads((E/'quality_checks.json').read_text('utf-8'))['selectionFinal'],'Boss selection is not final'
changed=[p for p,h in baseline.items() if not (R/p).is_file() or sha((R/p).read_bytes())!=h]
write('protected_files_verification.json',{'checked':len(baseline),'changed':changed,'status':'PASS' if not changed else 'FAIL'})
assert not changed,changed
apk=L/'build/app/outputs/flutter-apk/app-dev-debug.apk'
sources={
 'assets/pilot_levels.json':L/'assets/pilot_levels.json',
 'assets/pilot_copy.json':L/'assets/pilot_copy.json',
 'packages/sync_path_ui/assets/fonts/GameSansSubset.ttf':R/'packages/sync_path_ui/assets/fonts/GameSansSubset.ttf',
}
with zipfile.ZipFile(apk) as z:
 matches={key:z.read('assets/flutter_assets/'+key)==p.read_bytes() for key,p in sources.items()}
 pack=json.loads(z.read('assets/flutter_assets/assets/pilot_levels.json'))
 assert all(matches.values()) and len(pack['levels'])==100
 assert not any('assets/art/' in name or name.endswith('NotoSansKR.ttf') for name in z.namelist())
web={key:(L/'build/web/assets'/key).read_bytes()==p.read_bytes() for key,p in sources.items()}
assert all(web.values())
manifest=(E/'apk_manifest.txt').read_text('utf-8-sig')
assert "name='dev.shiftbell.experiments.sync_path_lab.dev'" in manifest
assert "versionCode='11'" in manifest and "versionName='0.9.0'" in manifest
target=L/'artifacts/finale100/app-dev-debug.apk';target.parent.mkdir(exist_ok=True,parents=True);shutil.copy2(apk,target)
previous=L/'artifacts/previous70/app-dev-debug.apk'
assert sha(previous.read_bytes())=='86b197206ca17fa9def98603af01403c184ca8f629c61ab1568e105abddd6d45'
write('build_artifact_verification.json',{'apk':str(target),'bytes':target.stat().st_size,'sha256':sha(target.read_bytes()),
 'assetMatchesSource':matches,'levels':100,'applicationId':'dev.shiftbell.experiments.sync_path_lab.dev',
 'versionName':'0.9.0','versionCode':11,'buildType':'dev debug','installedOnDevice':False,
 'web':{'build':'debug','assetsMatchSource':web,'mainDartJsBytes':(L/'build/web/main.dart.js').stat().st_size,
        'mainDartJsSha256':sha((L/'build/web/main.dart.js').read_bytes())},
 'previous70ApkPreserved':True,'protectedExistingFilesUnchanged':len(baseline)})
print('PASS: APK/web contain 100 levels and exact current assets. Existing protected files unchanged.')
