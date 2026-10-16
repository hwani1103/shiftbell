"""Capture this task's baseline without touching existing product files."""
import hashlib,json,shutil
from pathlib import Path
R=Path(__file__).resolve().parents[3]
E=R/'docs/next_version_27이후/game_implementation_v11'
E.mkdir(exist_ok=True)
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
baseline={}
for folder in ['lib','android','web','assets','test','tools','admin_dashboard','.github']:
 for p in (R/folder).rglob('*'):
  if p.is_file() and not any(x in p.parts for x in ['build','.dart_tool','.gradle','node_modules']):baseline[str(p.relative_to(R))]=digest(p)
for name in ['pubspec.yaml','pubspec.lock','AGENTS.md']:
 p=R/name
 if p.exists():baseline[name]=digest(p)
f=E/'protected_baseline.json'
if not f.exists():f.write_text(json.dumps(baseline,ensure_ascii=False,indent=2),'utf-8')
for name in ['pilot_levels.json','pilot_copy.json']:
 target=E/('previous_70_'+name)
 if not target.exists():shutil.copy2(R/'examples/sync_path_lab/assets'/name,target)
old=R/'docs/next_version_27이후/game_implementation_v10'
design=json.loads((old/'portal_design.json').read_text('utf-8'))
verify=json.loads((old/'portal_verification.json').read_text('utf-8'))
for d,v in zip(design['levels'],verify['levels']):
 print(d['id'], 'commands/domains',d['rawDomains'],'safe',v['safeDistinct'],'extra',d['minimumExtraDistance'],'cooperative',v['allGatesRequireCooperation'])
print('Protected files captured:',len(baseline))
