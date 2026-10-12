"""One-time reviewed resource migration. Candidate + original inputs are frozen."""
import json,re
from pathlib import Path
from generate_korean_only_copy import generate
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/next_version/후속재점검_2026-10-05'
keys=set(json.loads((OUT/'분리_후보.json').read_text('utf-8')))
ko_path=ROOT/'lib/l10n/app_ko.arb'
ko=json.loads(ko_path.read_text('utf-8'))
target=ROOT/'lib/l10n/korean_only/messages_ko.json'
target.parent.mkdir(exist_ok=True)
assert not target.exists(),'Migration already applied'
target.write_text(json.dumps({k:v for k,v in ko.items() if k.lstrip('@') in keys},ensure_ascii=False,indent=2)+'\n','utf-8')
generate()
for lang in ['ko','pt','de','en','hi']:
 p=ROOT/f'lib/l10n/app_{lang}.arb'; data=json.loads(p.read_text('utf-8'))
 for k in keys: data.pop(k,None);data.pop('@'+k,None)
 p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n','utf-8')
for p in (ROOT/'lib').rglob('*.dart'):
 if 'generated' in p.parts or p.name=='korean_only_copy.dart': continue
 s=p.read_text('utf-8'); original=s
 for key in keys:
  s=re.sub(r'(\w+)\.l10n\s*\.\s*'+key+r'\b',r'\1.koOnly.'+key,s)
  s=re.sub(r'\bl10n\s*\.\s*'+key+r'\b','KoreanOnlyCopy.fromLocalizations(l10n).'+key,s)
 if s!=original: p.write_text(s,'utf-8')
