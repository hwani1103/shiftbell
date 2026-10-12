"""One-time scoped UI cleanup; retain Korean text verbatim and log removed copy."""
import json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
records=[]
def literal_end(s,start):
 assert s[start]=="'"
 i=start+1
 while i<len(s):
  if s[i]=='\\':i+=2;continue
  if s.startswith('${',i):
   depth=1;i+=2
   while depth:
    if s[i]=="'":i=literal_end(s,i);continue
    if s[i]=='{':depth+=1
    if s[i]=='}':depth-=1
    i+=1
   continue
  if s[i]=="'":return i+1
  i+=1
 raise ValueError('Unclosed literal')
for name in ['lib/widgets/custom_alarm_widgets.dart','lib/widgets/onboarding_info_popups.dart']:
 p=ROOT/name;s=p.read_text('utf-8')
 pattern=r"\bko\s*\?\s*(?=')"
 while match:=re.search(pattern,s):
  start=match.end();end=literal_end(s,start)
  colon=re.match(r'\s*:\s*',s[end:]);assert colon
  foreign_start=end+colon.end();assert s[foreign_start]=="'"
  foreign_end=literal_end(s,foreign_start)
  records.append({'file':name,'before':s[match.start():foreign_end],'after':s[start:end], 'reason':'Korean-only UI, guarded entry and rebuilt modal; foreign first install cannot create this feature'})
  s=s[:match.start()]+s[start:end]+s[foreign_end:]
 s=re.sub(r"\s*final ko =\s*Localizations.localeOf\(context\).languageCode == 'ko';",'',s)
 s=s.replace("return Localizations.localeOf(context).languageCode == 'ko'\n          ? '이 원터치 알람은 해당 날짜에 이미 할당되어 있어요.'\n          : 'This one-tap alarm is already assigned to that day.';", "return '이 원터치 알람은 해당 날짜에 이미 할당되어 있어요.';")
 if name.endswith('custom_alarm_widgets.dart'):
  s=s.replace('builder: (context) => AlarmTimePicker(', 'builder: (context) => !context.usesKoreanFeatures ? const UnavailableFeature() : AlarmTimePicker(')
  s=s.replace('onTimeSelected: (time, _) async {','onTimeSelected: (time, _) async {\n                if (!context.mounted || !context.usesKoreanFeatures) return;')
  s=s.replace('if (confirmed != true) return;', 'if (confirmed != true || !context.mounted || !context.usesKoreanFeatures) return;')
  s=s.replace('if (ok != true || a.id == null) return;', 'if (ok != true || a.id == null || !context.mounted || !context.usesKoreanFeatures) return;')
  s=s.replace('if (context.mounted) {', 'if (context.mounted && context.usesKoreanFeatures) {')
 p.write_text(s,'utf-8')
(ROOT/'docs/next_version/후속재점검_2026-10-05/원터치_하드코딩_삭제원장.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),'utf-8')
print(len(records),'foreign hardcoded descriptions removed; one additional alreadyAssigned return removed')
