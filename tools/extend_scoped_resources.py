import json,re,csv
from pathlib import Path
from generate_korean_only_copy import generate
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/next_version/후속재점검_2026-10-05'
extra={'friendName','onboardingShiftLimitHint','workHoursDurationExcluded',
 'permissionAllow','permissionRequired','permissionRecommended','scheduleNotifyRegisterFailed',
 'scheduleDuplicateTimeSlot','scheduleMaxPerSlot','scheduleDeleteConfirmBody','scheduleEditTitle',
 'scheduleNewTitle','scheduleContentFieldLabel','scheduleTimeSectionLabel','scheduleNotifySectionLabel',
 'scheduleNotifyToggleLabel','scheduleNotifyDescription','scheduleNotifyOffsetQuestion',
 'scheduleNotifyOffsetOnTime','scheduleNotifyOffsetBefore','scheduleNotifyPastTimeWarning','scheduleCreateButton'}
ko_path=ROOT/'lib/l10n/app_ko.arb';ko=json.loads(ko_path.read_text('utf-8'))
p=ROOT/'lib/l10n/korean_only/messages_ko.json';data=json.loads(p.read_text('utf-8'))
data.update({k:v for k,v in ko.items() if k.lstrip('@') in extra})
p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n','utf-8');generate()
for lang in ['ko','pt','de','en','hi']:
 p=ROOT/f'lib/l10n/app_{lang}.arb';data=json.loads(p.read_text('utf-8'))
 for k in extra:data.pop(k,None);data.pop('@'+k,None)
 p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n','utf-8')
pattern='|'.join(sorted(extra))
for folder in ['lib','test','tools']:
 for p in (ROOT/folder).rglob('*.dart'):
  if 'generated' in p.parts or p.name=='korean_only_copy.dart':continue
  s=p.read_text('utf-8');before=s
  s=re.sub(r'(\w+)\s*\.\s*l10n\s*\.\s*('+pattern+r')\b',r'\1.koOnly.\2',s)
  if folder=='test':
   s=re.sub(r'\b\w+\s*\.\s*('+pattern+r')\b',r"KoreanOnlyCopy.forLocale('ko').\1",s)
   if s!=before and 'korean_only_copy.dart' not in s:s="import 'package:shiftbell/l10n/korean_only_copy.dart';\n"+s
  else:
   s=re.sub(r'\bl10n\s*\.\s*('+pattern+r')\b',r'KoreanOnlyCopy.fromLocalizations(l10n).\1',s)
  if s!=before:p.write_text(s,'utf-8')
(OUT/'추가_분리판정.json').write_text(json.dumps(sorted(extra),indent=2),'utf-8')
