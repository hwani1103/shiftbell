"""Refine both gate constraints on a frozen final board, with exact bitsets.

The choice prioritizes mandatory command total and detour distance, as requested
for the finale. Entropy is a tie breaker, not a measurement of human difficulty.
"""
import json,math,time
from author_finale100 import E,domains_for,combinations

def main():
 source=json.loads((E/'boss100_v7_probe_best.json').read_text('utf-8'))
 l=source['level'];ds=domains_for(l,cap=2000);plans,participation=combinations(ds,cap=50000)
 shortest=[min(r['length'] for r in d) for d in ds]
 extras=[sum(r['length']-shortest[k] for k,r in enumerate(rs)) for rs in plans]
 totals=[sum(len(r['endpoints']) for r in rs) for rs in plans]
 maxima=[max(len(r['endpoints']) for r in rs) for rs in plans]
 print('BASE',len(plans),'max extra',max(extras),'domains',list(map(len,ds)),flush=True)
 forbidden={tuple(l['goal']),*(tuple(u['start']) for u in l['units']),*(tuple(p[k]) for p in l.get('portals',[]) for k in ['entry','exit'])}
 events=[]
 for rs in plans:
  m={}
  for u,r in enumerate(rs):
   for t,c in r['points']:m.setdefault(c,[]).append((t,u))
  events.append(m)
 pool=set()
 # Every timed key/door pairing witnessed by the 250 longest safe base plans.
 for i in sorted(range(len(plans)),key=lambda i:(extras[i],totals[i]),reverse=True)[:250]:
  m=events[i]
  for trigger,acts in m.items():
   if trigger in forbidden:continue
   for door,visits in m.items():
    if door in forbidden or door==trigger:continue
    for t,u in acts:
     for td,v in visits:
      if u!=v and t>0 and 0<=td-t<=2:pool.add((trigger,door,td-t+1))
 gates=[];started=time.time()
 for gi,(trigger,door,duration) in enumerate(sorted(pool)):
  safe=0;good=0
  for i,m in enumerate(events):
   acts=m.get(trigger,[]);visits=m.get(door,[]);ok=True;coop=False
   for t,u in visits:
    active=[v for tt,v in acts if tt>0 and tt<=t<tt+duration]
    if not active:ok=False;break
    if u not in active:coop=True
   if ok:
    safe|=1<<i
    if visits and coop:good|=1<<i
  if good and safe.bit_count()<len(plans):gates.append((dict(trigger=trigger,door=door,openFor=duration),safe,good))
  if gi%100==0:print('GATES',gi,len(pool),'seconds',int(time.time()-started),flush=True)
 best=None
 for gi,(g,a,ag) in enumerate(gates):
  for h,b,bg in gates[gi+1:]:
   if {g['trigger'],g['door']}&{h['trigger'],h['door']}:continue
   inter=a&b;n=inter.bit_count()
   if not 1<=n<=35 or inter==a or inter==b or inter&~(ag&bg):continue
   indices=[];bits=inter
   while bits:
    bit=bits&-bits;bits-=bit;indices.append(bit.bit_length()-1)
   if min(maxima[i] for i in indices)!=14:continue
   total=min(totals[i] for i in indices);extra=min(extras[i] for i in indices)
   entropy=math.log2(math.prod(map(len,ds))/n);rank=(total,extra,entropy)
   if best is not None and rank<=best[0]:continue
   witness=plans[min(indices,key=lambda i:(totals[i],sum(r['length'] for r in plans[i])))]
   d=dict(source['design'],score=entropy+extra*.8+total*.28,canonicalSolutions=n,
    canonicalDomains=list(map(len,ds)),baseSolutions=len(plans),minimumRequiredMaxCommands=14,
    minimumTotalCommands=total,minimumExtraDistance=extra,constraintBits=entropy,
    conflictParticipation=participation,gateRemovalAdds=[b.bit_count()-n,a.bit_count()-n],
    witness=[dict(unitId=u['id'],endpoints=r['endpoints']) for u,r in zip(l['units'],witness)],
    author='boss100-gate-refinement-v8',gateProposals=len(pool),gateCandidates=len(gates),
    selectionPriority=['minimumTotalCommands','minimumExtraDistance','constraintBits'])
   final=dict(l,gates=[dict(g,id='1'),dict(h,id='2')]);best=(rank,final,d)
   (E/'boss100_refined.json').write_text(json.dumps(dict(level=final,design=d),ensure_ascii=False,indent=2)+'\n','utf-8')
   print('BEST','moves',total,'extra',extra,'safe',n,'score',round(d['score'],2),flush=True)
 if best is None:raise RuntimeError('No gate refinement')
 print('DONE',int(time.time()-started),flush=True)

if __name__=='__main__':main()
