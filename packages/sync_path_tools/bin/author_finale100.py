"""Finale author. Exhaustive canonical constant-speed routes; no straight splits.
A straight split has identical timing and can always be merged (except IN).
Thus canonical UNSAT at N also proves raw-command UNSAT at N. Reversals remain.
Independent Dart verifier must certify all exported candidates.
"""
import json,random,math,copy,sys,time
from pathlib import Path
from collections import deque
from campaign_geometry import geometry
R=Path(__file__).resolve().parents[3]; E=R/'docs/next_version_27이후/game_implementation_v11'; A=R/'examples/sync_path_lab/assets'
DIRS=[(1,0),(0,1),(-1,0),(0,-1)]
class Limit(Exception):pass

def graph_for(l):
 floor={(x,y) for y,row in enumerate(l['rows']) for x,c in enumerate(row) if c=='.'}
 goal=tuple(l['goal']); portals={tuple(p['entry']):tuple(p['exit']) for p in l.get('portals',[])}
 graph={};rev={c:[] for c in floor}
 for c in sorted(floor):
  graph[c]=[]
  if c==goal:continue
  for di,(dx,dy) in enumerate(DIRS):
   x,y=c
   while (x+dx,y+dy) in floor:
    x+=dx;y+=dy;end=(x,y);dest=portals.get(end,end)
    graph[c].append((end,dest,di));rev[dest].append(c)
    if end==goal:break
 dist={goal:0};q=deque([goal])
 while q:
  c=q.popleft()
  for prev in rev[c]:
   if prev not in dist:dist[prev]=dist[c]+1;q.append(prev)
 return graph,dist,portals

def domains_for(l,cap=1600,nodecap=160000):
 graph,dist,portals=graph_for(l);goal=tuple(l['goal']);size=l['width'];budget=l['maxCommands'];domains=[]
 for u in l['units']:
  routes=[];nodes=0
  def dfs(c,ends,points,edges,jumps,t,last):
   nonlocal nodes
   nodes+=1
   if nodes>nodecap:raise Limit()
   if c==goal:
    occ=0;eb=0
    for tt,(x,y) in points:
     if (x,y)!=goal:occ|=1<<(tt*size*size+y*size+x)
    for tt,a,b in edges:
     minimum=min(a[1]*size+a[0],b[1]*size+b[0]);edge=minimum*2+int(a[1]!=b[1]);eb|=1<<(tt*size*size*2+edge)
    routes.append(dict(endpoints=ends,points=points,edges=edges,jumps=jumps,length=t,occupancy=occ,edgeBits=eb))
    if len(routes)>cap:raise Limit()
    return
   if dist.get(c,999)>budget-len(ends):return
   for end,dest,di in graph[c]:
    if di==last:continue
    if dist.get(dest,999)>budget-len(ends)-1:continue
    dx,dy=DIRS[di];x,y=c;tt=t;ps=[];es=[]
    while (x,y)!=end:
     prev=(x,y);x+=dx;y+=dy;es.append((tt,prev,(x,y)));tt+=1;ps.append((tt,(x,y)))
    jump=end in portals
    if jump:ps.append((tt,dest))
    dfs(dest,ends+[end],points+ps,edges+es,jumps+([tt] if jump else []),tt,None if jump else di)
  dfs(tuple(u['start']),[],[(0,tuple(u['start']))],[],[],0,None)
  if not routes:return []
  domains.append(routes)
 return domains

def combinations(ds,cap=12000):
 matrices={};participation=[0]*len(ds)
 for i in range(len(ds)):
  for j in range(i+1,len(ds)):
   rows=[];unsafe=0
   for a in ds[i]:
    bits=0
    for k,b in enumerate(ds[j]):
     if not(a['occupancy']&b['occupancy'] or a['edgeBits']&b['edgeBits']):bits|=1<<k
     else:unsafe+=1
    rows.append(bits)
   matrices[i,j]=rows
   if unsafe:participation[i]+=1;participation[j]+=1
 out=[];nodes=0
 def rec(chosen):
  nonlocal nodes
  nodes+=1
  if nodes>150000:raise Limit()
  i=len(chosen)
  if i==len(ds):
   out.append([ds[k][r] for k,r in enumerate(chosen)])
   if len(out)>cap:raise Limit()
   return
  bits=(1<<len(ds[i]))-1
  for k,r in enumerate(chosen):bits&=matrices[k,i][r]
  while bits:
   b=bits&-bits;bits-=b;rec(chosen+[b.bit_length()-1])
 rec([])
 return out,participation

def maze(rng,size):
 floor={rng.choice([(x,y) for x in range(size) for y in range(size)])}
 candidates=[(x,y) for x in range(size) for y in range(size)]
 while True:
  possible=[c for c in candidates if c not in floor and sum((c[0]+dx,c[1]+dy) in floor for dx,dy in DIRS)==1]
  if not possible:break
  floor.add(rng.choice(possible))
 # Sometimes join branches, but keep the board readable without open 2x2 rooms.
 for _ in range(rng.randrange(3)):
  possible=[c for c in candidates if c not in floor and sum((c[0]+dx,c[1]+dy) in floor for dx,dy in DIRS)==2]
  if possible:floor.add(rng.choice(possible))
 return floor

def design_candidate(rng,budget,size,used,num,boss_geometry=False,diagnostics=None):
 def rejected(reason):
  if diagnostics is not None:diagnostics[reason]=diagnostics.get(reason,0)+1
 floor=maze(rng,size)
 l=dict(id='pending',revision=1,width=size,height=size,rows=[''.join('.' if (x,y) in floor else '#' for x in range(size)) for y in range(size)],goal=rng.choice(sorted(floor)),units=[],maxCommands=budget,requiredMechanics=['straight-motion','absorbing-shared-goal'])
 if boss_geometry:
  leaves=[c for c in sorted(floor) if sum((c[0]+dx,c[1]+dy) in floor for dx,dy in DIRS)==1]
  goals=rng.sample(leaves,min(5,len(leaves)))
  if not goals:return
  # Choose a deep endpoint before adding portals. Random interior goals rarely
  # permit four starts with a genuinely necessary 12-14-command route.
  l['goal']=max(goals,key=lambda goal:sorted(graph_for(dict(l,goal=goal))[1].values(),reverse=True)[3 if boss_geometry=='focused' else 0])
 if geometry(l,False) in used:return
 # Later rooms mix up to two reusable portal pairs; no new mechanics.
 pcount=rng.choices([0,1,2],[6,3,1] if boss_geometry else [2,5,3])[0]
 avail=sorted(floor-{tuple(l['goal'])})
 cells=rng.sample(avail,2*pcount)
 if pcount:l['portals']=[dict(id=str(i+1),entry=cells[2*i],exit=cells[2*i+1]) for i in range(pcount)];l['requiredMechanics'].append('endpoint-portals')
 graph,dist,_=graph_for(l)
 slack=3 if boss_geometry=='focused' and num>=98 else 4 if num>=95 else 3
 starts=[c for c in avail if c not in cells and budget-slack<=dist.get(c,999)<=budget and sum(abs(a-b) for a,b in zip(c,l['goal']))>=3]
 if len(starts)<4:return rejected('too_few_deep_starts')
 l['units']=[dict(id=chr(65+i),start=c) for i,c in enumerate(rng.sample(starts,4))]
 try:
  if boss_geometry=='domains':
   viable=[]
   for c in rng.sample(starts,min(12,len(starts))):
    try:
     domain=domains_for(dict(l,units=[dict(id='A',start=c)]),cap=900)[0]
    except (Limit,IndexError):continue
    if len(domain)>=3:viable.append((c,domain))
   if len(viable)<4:return rejected('too_few_bounded_starts')
   selected=rng.sample(viable,4)
   l['units']=[dict(id=chr(65+i),start=c) for i,(c,_) in enumerate(selected)]
   ds=[d for _,d in selected]
  else:ds=domains_for(l,cap=1800 if boss_geometry=='expanded' else 500 if num<95 else 900)
  if not ds or (min(map(len,ds))<3 if num<95 else sum(len(d)>=3 for d in ds)<3):return rejected('too_few_route_choices')
  plans,participation=combinations(ds,cap=40000 if boss_geometry in ('wide','expanded') else 12000)
 except Limit:return rejected('bounded_search_limit')
 if not plans or min(participation)<2:return rejected('collision_or_participation')
 shortest=[min(r['length'] for r in d) for d in ds]
 hardplans=sorted(plans,key=lambda rs:sum(r['length'] for r in rs),reverse=True)[:max(10,len(plans)//8)] if num>=95 else plans
 events=[]
 for rs in plans:
  m={}
  for u,r in enumerate(rs):
   for t,c in r['points']:m.setdefault(c,[]).append((t,u))
  events.append(m)
 def audit_gate(m,g):
  acts=m.get(g['trigger'],[]);visits=m.get(g['door'],[]);coop=False
  for t,u in visits:
   active=[v for tt,v in acts if tt>0 and tt<=t<tt+g['openFor']]
   if not active:return False,False,False
   if u not in active:coop=True
  return True,bool(visits),coop
 forbidden={tuple(l['goal']),*(tuple(u['start']) for u in l['units']),*cells}
 gos=[];seen=set()
 for trial in range(240 if num>=95 else 110):
  rs=rng.choice(hardplans if num>=95 and rng.random()<.8 else plans);u,v=rng.sample(range(4),2);tt,trigger=rng.choice(rs[u]['points'])
  if num>=95:
   nearby=[(t,c) for t,c in rs[v]['points'] if 0<=t-tt<=2 and c not in forbidden and c!=trigger]
   if not nearby:continue
   td,door=rng.choice(nearby)
  else:td,door=rng.choice(rs[v]['points'])
  if trigger in forbidden or door in forbidden or trigger==door or not 0<=td-tt<=4:continue
  duration=td-tt+1;key=(trigger,door,duration)
  if key in seen:continue
  seen.add(key);g=dict(id='1',trigger=trigger,door=door,openFor=duration)
  audit=[audit_gate(m,g) for m in events]
  safe={i for i,result in enumerate(audit) if result[0]}
  if not safe or len(safe)==len(plans):continue
  gos.append((g,safe,audit))
 best=None
 for gi,(g,safe,audit) in enumerate(gos):
  for h,other,haudit in gos[gi+1:]:
   if {g['trigger'],g['door']}&{h['trigger'],h['door']}:continue
   inter=sorted(safe&other)
   if not inter or len(inter)>=min(len(safe),len(other)) or len(inter)>35:continue
   survivors=[plans[i] for i in inter]
   if not all(all(audit[i]) and all(haudit[i]) for i in inter):continue
   if pcount and any(not any(r['jumps'] for r in rs) for rs in survivors):continue
   minmax=min(max(len(r['endpoints']) for r in rs) for rs in survivors)
   if minmax!=budget:continue
   extra=min(sum(r['length']-shortest[k] for k,r in enumerate(rs)) for rs in survivors)
   # A minimum of repeated timing detours; merely following a long corridor fails.
   threshold=4 if num<81 else 6 if num<91 else 8 if num<95 else 10
   if extra<threshold:continue
   bits=math.log2(math.prod(map(len,ds))/len(inter))
   minsum=min(sum(len(r['endpoints']) for r in rs) for rs in survivors)
   score=bits+extra*.8+minsum*.28
   if best is None or score>best[0]:
    witness=min(survivors,key=lambda rs:(sum(len(r['endpoints']) for r in rs),sum(r['length'] for r in rs)))
    record=dict(id=f'L{num:02}',score=score,canonicalDomains=list(map(len,ds)),canonicalSolutions=len(inter),baseSolutions=len(plans),minimumRequiredMaxCommands=minmax,minimumTotalCommands=minsum,minimumExtraDistance=extra,constraintBits=bits,conflictParticipation=participation,gateRemovalAdds=[len(other)-len(inter),len(safe)-len(inter)],witness=[dict(unitId=u['id'],endpoints=r['endpoints']) for u,r in zip(l['units'],witness)])
    best=(score,[g,dict(h,id='2')],record)
 if best:
  l['id']=f'L{num:02}';l['gates']=best[1];l['requiredMechanics'].append('timed-gates')
  return l,best[2]
 return rejected('gate_cooperation_or_difficulty')

def main():
 E.mkdir(exist_ok=True)
 pack=json.loads((E/'previous_70_pilot_levels.json').read_text('utf-8'));records=[]
 target=E/'finale_candidates.json'
 if target.exists():
  saved=json.loads(target.read_text('utf-8'));pack['levels']+=saved['levels'];records=saved['design']
 used={geometry(l,False) for l in pack['levels']}
 start=time.time()
 for num in range(71+len(records),101):
  budget=6+(num-71)//5 if num<96 else {96:11,97:11,98:12,99:12,100:14}[num]
  rng=random.Random(1001511+num*771);best=None
  for attempt in range(100000):
   out=design_candidate(rng,budget,8 if num==100 else 7,used,num)
   if out:
    if best is None or out[1]['score']>best[1]['score']:
     best=out
     if num>=95:
      print('BEST',num,round(best[1]['score'],1),best[1]['canonicalDomains'],'at',attempt,flush=True)
      (E/f'best_{num}.json').write_text(json.dumps(dict(level=best[0],design=best[1],attempt=attempt),ensure_ascii=False,indent=2)+'\n','utf-8')
    if attempt>100 and (num<95 or best[1]['score']>=53+(num-95)*2.4):break
   if attempt and attempt%2000==0:print('SEARCH',num,budget,attempt,'seconds',int(time.time()-start),flush=True)
  if best is None:raise RuntimeError(f'No candidate {num}')
  l,d=best;d['attempts']=attempt+1;d['seed']=1001511+num*771
  used.add(geometry(l,False));pack['levels'].append(l);records.append(d)
  target.write_text(json.dumps(dict(levels=pack['levels'][70:],design=records),ensure_ascii=False,indent=2)+'\n','utf-8')
  print('ACCEPT',num,'moves',budget,'domains',d['canonicalDomains'],'safe',d['canonicalSolutions'],'extra',d['minimumExtraDistance'],'score',round(d['score'],1),flush=True)
 print('DONE',int(time.time()-start),flush=True)
if __name__=='__main__':main()
