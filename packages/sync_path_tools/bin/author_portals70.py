"""Deterministic portal campaign search, exact integer/half-time occupancy.
No runtime engine/solver is imported. Chosen records require Dart certification.
"""
import json,random,math,copy
from collections import deque
from pathlib import Path
from campaign_geometry import geometry
R=Path(__file__).resolve().parents[3];E=R/'docs/next_version_27이후/game_implementation_v10';A=R/'examples/sync_path_lab/assets'
DIRS=[(1,0),(0,1),(-1,0),(0,-1)]
class Limit(Exception):pass

def analyze(l):
 size=l['width']; goal=tuple(l['goal']);budget=l['maxCommands']; p=l['portals'][0];entry=tuple(p['entry']);exit=tuple(p['exit'])
 floor={(x,y) for y,row in enumerate(l['rows']) for x,c in enumerate(row) if c=='.'}
 graph={};rev={c:[] for c in floor}
 for c in sorted(floor):
  graph[c]=[]
  if c==goal:continue
  for dx,dy in DIRS:
   x,y=c
   while (x+dx,y+dy) in floor:
    x+=dx;y+=dy;end=(x,y);dest=exit if end==entry else end
    graph[c].append((end,dest,(dx,dy)));rev[dest].append(c)
    if end==goal:break
 dist={goal:0};q=deque([goal])
 while q:
  c=q.popleft()
  for prev in rev[c]:
   if prev not in dist:dist[prev]=dist[c]+1;q.append(prev)
 domains=[];nodes=0
 for u in l['units']:
  groups={};raw=0
  def dfs(c,ends,points,edges,jumps,t):
   nonlocal nodes,raw
   nodes+=1
   if nodes>40000:raise Limit()
   if c==goal:
    raw+=1
    if raw>260:raise Limit()
    key=(tuple(edges),tuple(jumps))
    if key in groups:groups[key]['weight']+=1;return
    occ=0;eb=0
    for time,(x,y) in points:
     if (x,y)!=goal:occ |= 1 << (time*size*size+y*size+x)
    for time,a,b in edges:
     minimum=min(a[1]*size+a[0],b[1]*size+b[0]);edge=minimum*2+int(a[1]!=b[1]);eb|=1 << (time*size*size*2+edge)
    groups[key]=dict(endpoints=ends,points=points,edges=edges,jumps=jumps,length=t,weight=1,occupancy=occ,edgeBits=eb)
    if len(groups)>70:raise Limit()
    return
   if dist.get(c,999)>budget-len(ends):return
   for end,dest,(dx,dy) in graph[c]:
    path=[];es=[];x,y=c;time=t
    while (x,y)!=end:
     prev=(x,y);x+=dx;y+=dy;es.append((time,prev,(x,y)));time+=1;path.append((time,(x,y)))
    js=[]
    if end==entry:js=[time];path.append((time,exit))
    dfs(dest,ends+[end],points+path,edges+es,jumps+js,time)
  try:dfs(tuple(u['start']),[],[(0,tuple(u['start']))],[],[],0)
  except Limit:return None
  if not groups:return None
  domains.append(list(groups.values()))
 matrices={};participation=[0]*len(domains)
 for i in range(len(domains)):
  for j in range(i+1,len(domains)):
   table=[];unsafe=0
   for a in domains[i]:
    bits=0
    for k,b in enumerate(domains[j]):
     if not(a['occupancy']&b['occupancy'] or a['edgeBits']&b['edgeBits']):bits|=1<<k
     else:unsafe+=1
    table.append(bits)
   matrices[i,j]=table
   if unsafe:participation[i]+=1;participation[j]+=1
 solutions=[];searchnodes=0;rawsafe=0
 def search(chosen):
  nonlocal searchnodes,rawsafe
  searchnodes+=1
  if searchnodes>50000:raise Limit()
  i=len(chosen)
  if i==len(domains):
   solutions.append(chosen);rawsafe+=math.prod(domains[k][r]['weight'] for k,r in enumerate(chosen))
   if len(solutions)>500 or rawsafe>3000:raise Limit()
   return
  bits=(1<<len(domains[i]))-1
  for k,r in enumerate(chosen):bits &= matrices[k,i][r]
  while bits:
   bit=bits&-bits;bits-=bit;search(chosen+[bit.bit_length()-1])
 try:search([])
 except Limit:return None
 if not solutions:return None
 return domains,solutions,participation

def gate_pass(rs,g):
 acts=[(t,u) for u,r in enumerate(rs) for t,c in r['points'] if t>0 and tuple(c)==tuple(g['trigger'])]
 visits=[(t,u) for u,r in enumerate(rs) for t,c in r['points'] if tuple(c)==tuple(g['door'])]
 cooperative=False
 for t,u in visits:
  active=[v for tt,v in acts if tt<=t<tt+g['openFor']]
  if not active:return False,False,False
  if u not in active:cooperative=True
 return True,bool(visits),cooperative

def main():
 pack=json.loads((E/'previous_50_pilot_levels.json').read_text('utf-8'));copies=json.loads((E/'previous_50_pilot_copy.json').read_text('utf-8'))
 used={geometry(l,False) for l in pack['levels']};rng=random.Random(701015);pool=[]
 for f in ['candidates50.jsonl','candidates50_multi.jsonl']:
  pool += [json.loads(s)['level'] for s in (R/'docs/next_version_27이후/game_implementation_v6'/f).read_text('utf-8').splitlines()]
 records=[]
 for num in range(51,71):
  n=2 if num<=53 else 3 if num<=62 else 4
  gate_count=0 if num<60 else 1 if num<66 else 2
  target=4+(num-51)*1.1 if num<60 else 14+(num-60)*1.15
  options=[l for l in pool if len(l['units'])==n and l['maxCommands']<=5 and geometry(l,False) not in used]
  best=None;accepted=0
  for attempt in range(12000):
   l=copy.deepcopy(rng.choice(options));floor=[(x,y) for y,row in enumerate(l['rows']) for x,c in enumerate(row) if c=='.'];forbid={tuple(l['goal']),*(tuple(u['start']) for u in l['units'])}
   avail=[c for c in floor if c not in forbid];entry,exit=rng.sample(avail,2)
   if sum(abs(a-b) for a,b in zip(entry,exit))<3 or sum(abs(a-b) for a,b in zip(exit,l['goal']))<2:continue
   if rng.random()<.75:l['maxCommands']=max(2,l['maxCommands']-1)
   l['portals']=[dict(id='1',entry=entry,exit=exit)];out=analyze(l)
   if not out:continue
   ds,solutions,participation=out;plans=[[ds[k][v] for k,v in enumerate(s)] for s in solutions]
   # Every ball has substantial travel and a meaningful choice, even in the final levels.
   if min(min(r['length'] for r in d) for d in ds)<3:continue
   if num>=53 and (min(participation)<1 or min(map(len,ds))<2):continue
   survivors=list(range(len(plans)));gates=[]
   if gate_count:
    forbidden=forbid|{entry,exit};gos=[];seen=set()
    # Bounded proposal sampling avoids spending time on thousands of equivalent
    # trigger/door placements in one rejected layout.
    proposals=[]
    for trial in range(180):
     rs=rng.choice(plans);u,v=rng.sample(range(n),2)
     t,trigger=rng.choice(rs[u]['points']);td,door=rng.choice(rs[v]['points'])
     if trigger in forbidden or door in forbidden or trigger==door or not 0<=td-t<=4:continue
     duration=max(2,td-t+1);key=(trigger,door,duration)
     if key in seen:continue
     seen.add(key);proposals.append(dict(id='1',trigger=trigger,door=door,openFor=duration))
    for g in proposals:
     safe=[i for i,rr in enumerate(plans) if gate_pass(rr,g)[0]]
     if not safe or len(safe)==len(plans):continue
     if not all(all(gate_pass(plans[i],g)) for i in safe):continue
     gos.append((g,safe))
    choices=[]
    for g,safe in gos:
     if gate_count==1:choices.append(([g],safe));continue
     for h,other in gos:
      if {g['trigger'],g['door']}&{h['trigger'],h['door']}:continue
      inter=sorted(set(safe)&set(other))
      if inter and len(inter)<len(safe) and len(inter)<len(other):choices.append(([g,dict(h,id='2')],inter))
    if not choices:continue
   else:choices=[([],survivors)]
   for gates,survivors in choices:
    safeplans=[plans[i] for i in survivors]
    # Portals must be essential in every safe plan, not just decorative shortcuts.
    if any(not any(r['jumps'] for r in rs) for rs in safeplans):continue
    if len(survivors)>70:continue
    minlen=[min(r['length'] for r in d) for d in ds]
    extra=min(sum(r['length']-minlen[k] for k,r in enumerate(rs)) for rs in safeplans)
    bits=math.log2(math.prod(map(len,ds))/len(survivors))
    score=n+bits*.65+extra*.55+gate_count*1.4+min(sum(len(r['endpoints']) for r in rs) for rs in safeplans)*.12
    if num>=54 and extra<2:continue
    if num>=60 and records and score<records[-1]['score']-1:continue
    if num>=54 and num<60 and score<records[-1]['score']-.5:continue
    quality=abs(score-target)+(len(survivors)>20)*2
    if best is None or quality<best[0]:
     witness=min(safeplans,key=lambda rs:(sum(r['length'] for r in rs),sum(len(r['endpoints']) for r in rs)))
     record=dict(id=f'L{num:02}',score=score,distinctSolutions=len(survivors),rawSolutions=sum(math.prod(r['weight'] for r in plans[i]) for i in survivors),rawDomains=[sum(r['weight'] for r in d) for d in ds],temporalDomains=list(map(len,ds)),baseSolutions=len(plans),constraintBits=bits,minimumExtraDistance=extra,conflictParticipation=participation,minimumPortalUsers=min(sum(bool(r['jumps']) for r in rs) for rs in safeplans),witness=[dict(unitId=u['id'],endpoints=r['endpoints']) for u,r in zip(l['units'],witness)],attempt=attempt)
     best=(quality,copy.deepcopy(l),copy.deepcopy(gates),record)
   if best and best[0]<.5 and attempt>100:break
   if best and attempt>1800:break
  if not best:raise RuntimeError(f'No level {num}')
  _,l,gates,record=best;l['id']=record['id'];l['requiredMechanics']=['straight-motion','absorbing-shared-goal','endpoint-portals'];
  if gates:l['gates']=gates;l['requiredMechanics'].append('timed-gates')
  used.add(geometry(l,False));pack['levels'].append(l);records.append(record)
  titles=['이어지는 두 칸','출구에서 다시','같은 출구, 다른 순간','먼저 갈 공','지름길의 대가','한 바퀴의 여유','길을 나누다','교차하는 시간','출구를 비워 줘','넘어가서 열어 줘','먼 곳의 스위치','열리는 순서','닫히기 전에','돌아가는 이유','시간을 나누다','두 문 사이','엇갈린 지름길','먼저 열고 건너기','네 공의 약속','마지막 연결']
  ko=[];en=[];p=l['portals'][0]
  for u,r in zip(l['units'],record['witness']):
   c=u['start'];ks=[];es=[]
   for end in r['endpoints']:
    dx=end[0]-c[0];dy=end[1]-c[1];d=abs(dx)+abs(dy);kd,ed=('오른쪽','right') if dx>0 else ('왼쪽','left') if dx<0 else ('아래','down') if dy>0 else ('위','up');ks.append(f'{kd} {d}칸');es.append(f'{d} {ed}');c=end
    if tuple(end)==tuple(p['entry']):ks[-1]+=' (포탈)';es[-1]+=' (portal)';c=p['exit']
   ko.append(u['id']+': '+' → '.join(ks));en.append(u['id']+': '+' → '.join(es))
  copies[l['id']]=dict(titleKo=titles[num-51],titleEn=f'Portal connections {num-50}',hintsKo=['입구를 끝점으로 탭하면 출구로 즉시 이동해요. 입구를 그냥 지나치면 이동하지 않아요.', '출구를 비우는 시각을 맞춰 보세요. 가까운 길이 항상 안전한 길은 아니에요.' if not gates else '포탈로 줄어든 이동 시간을 이용해 다른 공이 지날 문을 열어 주세요.', '한 가지 안전한 경로예요.\n'+'\n'.join(ko)],hintsEn=['End a move on IN to transfer instantly to OUT. Merely crossing IN does not transfer.', 'Leave the exit clear when the next ball arrives.' if not gates else 'Use the shortcut to open a gate in time for another ball.', 'One safe complete plan:\n'+'\n'.join(en)])
  if num in [51,54,60,66]:copies[l['id']].update(chapterKo={51:'51–53 · 포탈 익히기',54:'54–59 · 출구의 타이밍',60:'60–65 · 포탈과 스위치',66:'66–70 · 두 문과 포탈'}[num],chapterEn={51:'51–53 · Portal basics',54:'54–59 · Exit timing',60:'60–65 · Portals & switches',66:'66–70 · Two gates & a portal'}[num])
  print(num,'score',round(record['score'],2),'safe',record['distinctSolutions'],'raw',record['rawSolutions'],'extra',record['minimumExtraDistance'],'attempt',record['attempt'],flush=True)
  (E/'portal_design.json').write_text(json.dumps(dict(levels=records),ensure_ascii=False,indent=2)+'\n','utf-8')
  for name,data in [('pilot_levels.json',pack),('pilot_copy.json',copies)]: (A/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n','utf-8')
if __name__=='__main__':main()
