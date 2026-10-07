"""Freeze this follow-up's inputs and enumerate references; no reachability claims."""
import json, re, hashlib, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/next_version/후속재점검_2026-10-05'
OUT.mkdir(exist_ok=True)
sources = {str(p.relative_to(ROOT)).replace('\\', '/'): p.read_text('utf-8')
           for base, ext in [('lib', '*.dart'), ('android/app/src/main', '*.kt'),
                             ('android/app/src/main', '*.xml')]
           for p in (ROOT/base).rglob(ext) if 'generated' not in p.parts}
arbs = {lang: json.loads((ROOT/f'lib/l10n/app_{lang}.arb').read_text('utf-8'))
        for lang in ['ko', 'pt', 'de', 'en', 'hi']}
refs = {key: [] for key in arbs['ko'] if not key.startswith('@')}
for path, source in sources.items():
    for i, line in enumerate(source.splitlines(), 1):
        for key in set(re.findall(r'\.(\w+)\b', line)) & refs.keys():
            refs[key].append(f'{path}:{i}')
snapshot = {'arbs': arbs, 'sources_sha256': {p: hashlib.sha256(t.encode()).hexdigest()
                                          for p, t in sources.items()}, 'references': refs}
dest = OUT/'시작_자료.json'
if not dest.exists():
    dest.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2), 'utf-8')
    status = subprocess.run(['git', 'status', '--short'], cwd=ROOT, capture_output=True).stdout
    (OUT/'시작_git_status.txt').write_bytes(status)
print('Frozen snapshot:', dest)
for key, value in arbs['ko'].items():
    if key.startswith('@'): continue
    if re.search(r'customAlarm|friend|sleep|condition|themeInitial|themeUnderline|themeEventChip|themeEditorial|ScheduleTab|ScheduleManagement|fixedAlarmSkipped', key, re.I):
        print(key, value[:100].replace('\n', ' / '), '; '.join(refs[key]))
