"""Assemble candidates for audit; --publish requires all thirty levels."""
import json,sys
from pathlib import Path
from campaign_geometry import geometry
R=Path(__file__).resolve().parents[3]; E=R/'docs/next_version_27이후/game_implementation_v11'; A=R/'examples/sync_path_lab/assets'
saved=json.loads((E/'finale_candidates.json').read_text('utf-8'))
preview='--publish-preview' in sys.argv
if preview:
 for n in range(71+len(saved['levels']),101):
  candidate=json.loads((E/f'best_{n}_parallel.json').read_text('utf-8'))
  saved['levels'].append(candidate['level']);saved['design'].append(candidate['design'])
pack=json.loads((E/'previous_70_pilot_levels.json').read_text('utf-8'))
# Order each move-budget band by the same documented difficulty heuristic.
pairs=list(zip(saved['levels'],saved['design']))
ordered=[]
for b in sorted({l['maxCommands'] for l,d in pairs}):
 ordered += sorted([(l,d) for l,d in pairs if l['maxCommands']==b],key=lambda pair:pair[1]['score'])
records=[]
for n,(l,d) in enumerate(ordered,71):
 d=dict(d,sourceId=d['id']); l=dict(l,id=f'L{n:02}');d['id']=l['id']
 pack['levels'].append(l);records.append(d)
def write(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n','utf-8')
write(E/'candidate_pack.json',pack);write(E/'finale_design.json',{'levels':records})
if '--publish' not in sys.argv and not preview:
 print('Audit pack',len(pack['levels']));sys.exit()
assert len(records)==30 and len(pack['levels'])==100
assert len({geometry(l,False) for l in pack['levels']})==100
copy=json.loads((E/'previous_70_pilot_copy.json').read_text('utf-8'))
names={'ko':['파란 원무늬 공','빨간 줄무늬 공','보라 십자무늬 공','초록 마름모무늬 공'],
       'en':['blue dotted ball','red striped ball','purple cross ball','green diamond ball']}
for entry in copy.values():
 for key in list(entry):
  if key.startswith(('title','chapter')):del entry[key]
 for language in ['ko','en']:
  key='hints'+language.title()
  def clean(s):
   for i,name in enumerate(names[language]):
    letter=chr(65+i)
    s=s.replace(letter+':',name+':').replace(letter+'의',name+'의')
    s=s.replace('Adjust '+letter+' first','Adjust the '+name+' first')
   s=s.replace('번개 스위치','열쇠').replace('번개','열쇠').replace('스위치','열쇠').replace('lightning switch','key').replace('switch','key')
   s=s.replace('같은 번호','같은 색').replace('문에 남은 시간이 표시돼요.','테두리 눈금이 남은 시간을 보여줘요.')
   s=s.replace('1번 문','금색 문').replace('2번 문','자홍색 문').replace('gate 1','gold door').replace('gate 2','magenta door')
   s=s.replace('IN','입구' if language=='ko' else 'the entrance').replace('OUT','출구' if language=='ko' else 'the exit')
   return s
  entry[key]=[clean(s) for s in entry[key]]
for l,d in zip(pack['levels'][70:],records):
 hints={}
 portals={tuple(p['entry']):p['exit'] for p in l.get('portals',[])}
 for lang in ['ko','en']:
  lines=[]
  for i,(u,r) in enumerate(zip(l['units'],d['witness'])):
   c=u['start'];steps=[]
   for end in r['endpoints']:
    dx,dy=end[0]-c[0],end[1]-c[1];length=abs(dx)+abs(dy)
    ko,en=('오른쪽','right') if dx>0 else ('왼쪽','left') if dx<0 else ('아래','down') if dy>0 else ('위','up')
    step=f'{ko} {length}칸' if lang=='ko' else f'{length} {en}'
    if tuple(end) in portals:step+=' (포탈)' if lang=='ko' else ' (portal)'
    steps.append(step);c=portals.get(tuple(end),end)
   lines.append(names[lang][i]+': '+' → '.join(steps))
  hints['hints'+lang.title()]=[
   '먼저 두 열쇠와 문을 연결해서 보세요. 누가 문을 열고 누가 통과할지 함께 계획해야 해요.' if lang=='ko' else 'Pair both keys with their doors. Plan who opens each door and who crosses it.',
   '짧은 길만으로는 풀리지 않아요. 왕복과 우회로 시간을 벌고, 다른 공의 다음 교차도 확인하세요.' if lang=='ko' else 'Shortest paths cannot solve this room. Use returns and detours to create time, then check the next crossing too.',
   ('한 가지 안전한 경로예요.\n' if lang=='ko' else 'One safe complete plan:\n')+'\n'.join(lines)]
  copy[l['id']]=hints
write(A/'pilot_levels.json',pack);write(A/'pilot_copy.json',copy)
write(E/'quality_checks.json',{'levels':100,'selectionFinal':not preview,'uniqueFloorGeometriesIgnoringRotationReflection':100,
 'first70GameplayPreserved':pack['levels'][:70]==json.loads((E/'previous_70_pilot_levels.json').read_text('utf-8'))['levels'],
 'maximumDoors':max(len(l.get('gates',[])) for l in pack['levels']), 'maximumPortalPairs':max(len(l.get('portals',[])) for l in pack['levels']),
 'finaleRequiredMoveBudgets':[l['maxCommands'] for l in pack['levels'][70:]],'finalBoard':[pack['levels'][-1]['width'],pack['levels'][-1]['height']],
 'humanPlaytest':'NOT_TESTED'})
print('Published 100 levels, identity preserved; titles removed.')
