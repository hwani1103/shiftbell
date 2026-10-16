"""Select novel layouts and essential cooperative timed gates; bounded offline authoring."""
import json,random,math,copy
from pathlib import Path
from author_campaign50 import analyze
from campaign_geometry import geometry
R=Path(__file__).resolve().parents[3];E=R/'docs/next_version_27이후/game_implementation_v8';E.mkdir(exist_ok=True)
A=R/'examples/sync_path_lab/assets';old=R/'docs/next_version_27이후/game_implementation_v7'
pack=json.loads((old/'previous_30_pilot_levels.json' if (old/'previous_30_pilot_levels.json').exists() else A/'pilot_levels.json').read_text('utf-8'));copies=json.loads((old/'previous_30_pilot_copy.json' if (old/'previous_30_pilot_copy.json').exists() else A/'pilot_copy.json').read_text('utf-8'))
# Preserve the thirty-level artifact before changing current assets.
for name in ['pilot_levels.json','pilot_copy.json']:
 target=old/('previous_30_'+name)
 if not target.exists():target.write_bytes((A/name).read_bytes())
used={geometry(l,False) for l in pack['levels']};rng=random.Random(801014)
pool=[]
for name in ['candidates50.jsonl','candidates50_multi.jsonl']:
 pool += [json.loads(s) for s in (R/'docs/next_version_27이후/game_implementation_v6'/name).read_text('utf-8').splitlines()]

def events(routes,g):
 activ=[];visits=[]
 for u,r in enumerate(routes):
  for t,c in enumerate(r['path'][1:-1],1):
   if list(c)==g['trigger']:activ.append((t,u))
   if list(c)==g['door']:visits.append((t,u))
 cooperative=False
 for t,u in visits:
  available=[v for v in activ if v[0]<=t<v[0]+g['openFor']]
  if not available:return False,False
  # A gate visit must actually depend on another ball, not an optional helper.
  if not any(v==u for _,v in available):cooperative=True
 return bool(visits),cooperative

def evaluate(chosen,gates):
 return all(all(events(rs,g)) for g in gates for rs in [chosen])

selected=[]
for number in range(31,51):
 units=2 if number<=33 else 3 if number<=41 else 4
 count=1 if number<=41 else 2
 target=(3+(number-31)*.8) if number<=41 else 12+(number-42)*1.35
 candidates=[p for p in pool if len(p['level']['units'])==units and p['level']['maxCommands']<=5 and geometry(p['level'],False) not in used]
 candidates.sort(key=lambda p:abs(p['metrics']['score']-target))
 best=None
 for candidate in candidates[:220]:
  level=candidate['level'];out=analyze(level,True)
  if not out:continue
  metrics,domains,solutions=out
  plans=[[domains[k][v] for k,v in enumerate(s)] for s in solutions]
  forbidden={tuple(level['goal']),*(tuple(u['start']) for u in level['units'])}
  options=[];seen=set()
  for routes in plans[:35]:
   for u,a in enumerate(routes):
    for v,b in enumerate(routes):
     if u==v:continue
     for t,trigger in enumerate(a['path'][1:-1],1):
      if trigger in forbidden:continue
      for td,door in enumerate(b['path'][1:-1],1):
       if door in forbidden or trigger==door or not 0<=td-t<=5:continue
       duration=max(2,td-t+1)
       if number<=33:duration=max(4,duration)
       key=(trigger,door,duration)
       if key in seen:continue
       seen.add(key);g=dict(id='1',trigger=list(trigger),door=list(door),openFor=duration)
       # Every surviving solution must visit and require another unit's switch.
       safe=[i for i,rs in enumerate(plans) if all(events(rs,g))]
       all_pass=[i for i,rs in enumerate(plans) if all(any(tt<=td<tt+duration for uu,rr in enumerate(rs) for tt,cc in enumerate(rr['path']) if list(cc)==g['trigger']) for rr in rs for td,cc in enumerate(rr['path']) if list(cc)==g['door'])]
       if not safe or safe!=all_pass or len(safe)>=len(plans):continue
       options.append((g,safe))
       if len(options)>=70:break
      if len(options)>=70:break
     if len(options)>=70:break
    if len(options)>=70:break
   if len(options)>=70:break
  for g,safe in options:
   gates=[g];survive=safe
   if count==2:
    pair=None
    for h,other in options:
     if {tuple(g['trigger']),tuple(g['door'])}&{tuple(h['trigger']),tuple(h['door'])}:continue
     inter=sorted(set(safe)&set(other))
     if inter and len(inter)<len(safe) and len(inter)<len(other):pair=(h,inter);break
    if pair is None:continue
    h,survive=pair;h=dict(h,id='2');gates=[g,h]
   # Each device eliminates safe base plans and is indispensable in every solution.
   score=metrics['score']+math.log2(len(plans)/len(survive))*.65+count
   if number>=34 and selected and score<selected[-1]['gateScore']-.5:continue
   witness=plans[survive[0]]
   record=dict(previousCandidate=level['id'],gateScore=score,baseMetrics=metrics,
     distinctSolutions=len(survive),rawSolutions=sum(math.prod(r['weight'] for r in plans[i]) for i in survive),
     baseDistinctSolutions=len(plans),witness=[dict(unitId=u['id'],endpoints=r['endpoints']) for u,r in zip(level['units'],witness)])
   quality=abs(score-(target+2*count)) + (len(survive)>20)*5
   if best is None or quality<best[0]:best=(quality,copy.deepcopy(level),gates,record)
  if best and best[0]<1:break
 if best is None:raise RuntimeError(f'No essential cooperative gate layout for {number}')
 _,level,gates,record=best;level['id']=f'L{number:02}';level['gates']=gates;level['requiredMechanics'].append('timed-gates');used.add(geometry(level,False));pack['levels'].append(level);record['id']=level['id'];selected.append(record)
 title=['문을 열어 줘','열린 순간','한 박자 맞추기'][number-31] if number<=33 else f'함께 여는 길 {number-33}'
 ko=[];en=[]
 for u,route in zip(level['units'],record['witness']):
  start=u['start'];ks=[];es=[]
  for end in route['endpoints']:
   dx=end[0]-start[0];dy=end[1]-start[1];n=abs(dx)+abs(dy);direction=('오른쪽','right') if dx>0 else ('왼쪽','left') if dx<0 else ('아래','down') if dy>0 else ('위','up');ks.append(f'{direction[0]} {n}칸');es.append(f'{n} {direction[1]}');start=end
  ko.append(u['id']+': '+' → '.join(ks));en.append(u['id']+': '+' → '.join(es))
 cp=dict(titleKo=title,titleEn=f'Together through gates {number-30}',hintsKo=['번개 스위치를 지나면 같은 번호의 문이 열려요. 문에 남은 시간이 표시돼요.','다른 공이 문을 통과할 때 열려 있도록 스위치까지 가는 경로를 맞춰 보세요.','한 가지 안전한 경로예요.\n'+'\n'.join(ko)],hintsEn=['Cross a lightning switch to open its matching gate. The gate shows time remaining.','Plan when one ball crosses the switch so another can pass through.','One safe complete plan:\n'+'\n'.join(en)])
 if number in [31,36,41,46]:cp.update(chapterKo=f'{number}–{number+4} · 함께 여는 문',chapterEn=f'{number}–{number+4} · Cooperative gates')
 copies[level['id']]=cp
 print(number,'units',units,'gates',count,'safe',record['distinctSolutions'],'score',round(record['gateScore'],2),flush=True)
 (E/'gate_design.json').write_text(json.dumps(dict(levels=selected),ensure_ascii=False,indent=2),'utf-8')
pack['packId']='dev-campaign-50-gates'
for name,data in [('pilot_levels.json',pack),('pilot_copy.json',copies)]: (A/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n','utf-8')

