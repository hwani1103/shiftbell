"""Search all unfinished boss rooms fairly; checkpoint bounded calculations.

Uses ordinary local process workers. Frozen candidate JSON, not a random seed
alone, is the authoritative input to the independent Dart certificate.
"""
import concurrent.futures,json,time
from author_finale100 import E
from author_boss100_targeted import batch
from campaign_geometry import geometry

def main():
 target=E/'finale_candidates.json';saved=json.loads(target.read_text('utf-8'))
 old=json.loads((E/'previous_70_pilot_levels.json').read_text('utf-8'))
 used={geometry(l,False) for l in old['levels']+saved['levels']}
 pending=list(range(71+len(saved['levels']),101));best={};offset={n:0 for n in pending}
 checkpoint=E/'boss_wide_state.json'
 if checkpoint.exists():
  offset.update({int(n):v for n,v in json.loads(checkpoint.read_text('utf-8')).items() if int(n) in pending})
 for n in pending:
  path=E/f'best_{n}_parallel.json'
  if path.exists():
   data=json.loads(path.read_text('utf-8'))
   if data['design'].get('author') in ('boss100-aligned-gate-seeds-v3','boss100-deep-goal-seeds-v4','boss100-wide-combinations-v6') and geometry(data['level'],False) not in used:best[n]=(data['level'],data['design'])
 started=time.time();rounds=0
 with concurrent.futures.ProcessPoolExecutor(max_workers=6) as pool:
  jobs={}
  def submit():
    n=min(pending,key=lambda k:offset[k])
    if offset[n]>=100000:raise RuntimeError(f'No certified boss threshold: {n}')
    budget=10 if n==95 else {96:11,97:11,98:12,99:12,100:14}[n]
    jobs[pool.submit(batch,(n,budget,used,offset[n]))]=n;offset[n]+=12
  for n in list(pending):
   if n in best and best[n][1]['score']>=53+(n-95)*2.4:
    pending.remove(n);used.add(geometry(best[n][0],False))
  for _ in range(6):
   if pending:submit()
  while jobs:
   done,_=concurrent.futures.wait(jobs,return_when=concurrent.futures.FIRST_COMPLETED)
   for future in done:
    n=jobs.pop(future)
    out=future.result()
    if n in pending and out and geometry(out[0],False) not in used and (n not in best or out[1]['score']>best[n][1]['score']):
     best[n]=out
     (E/f'best_{n}_parallel.json').write_text(json.dumps(dict(level=out[0],design=out[1]),ensure_ascii=False,indent=2)+'\n','utf-8')
     print('BEST',n,round(out[1]['score'],2),'extra',out[1]['minimumExtraDistance'],'domains',out[1]['canonicalDomains'],flush=True)
    if n in pending and n in best and best[n][1]['score']>=53+(n-95)*2.4:
      pending.remove(n);used.add(geometry(best[n][0],False))
      print('READY',n,'score',round(best[n][1]['score'],2),flush=True)
    if pending:submit()
   checkpoint.write_text(json.dumps(offset,indent=2)+'\n','utf-8')
   rounds+=1
   if rounds%40==0:print('SEARCH',offset,'seconds',int(time.time()-started),flush=True)
 for n in sorted(best):
  l,d=best[n];saved['levels'].append(l);saved['design'].append(d)
 target.write_text(json.dumps(saved,ensure_ascii=False,indent=2)+'\n','utf-8')
 print('DONE',int(time.time()-started),flush=True)

if __name__=='__main__':main()
