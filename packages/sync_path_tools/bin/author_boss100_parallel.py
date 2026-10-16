"""Bounded parallel candidate calculations for the six boss rooms.
No agents or network services: independent deterministic Python search seeds.
Only the parent writes the candidate ledger, after each complete batch.
"""
import concurrent.futures,json,random,time,argparse
from author_finale100 import E,design_candidate
from campaign_geometry import geometry

def batch(args):
 num,budget,used,start=args;best=None
 for attempt in range(start,start+12):
  seed=881000+num*100000+attempt
  out=design_candidate(random.Random(seed),budget,8 if num==100 else 7,used,num)
  if out and (best is None or out[1]['score']>best[1]['score']):
   out[1].update(seed=seed,attempts=attempt+1,author='boss100-aligned-gate-seeds-v3')
   best=out
 return best

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--workers',type=int,default=6);parser.add_argument('--offset',type=int,default=0);args=parser.parse_args()
 if not 1<=args.workers<=8:raise ValueError('workers must be 1..8')
 target=E/'finale_candidates.json';saved=json.loads(target.read_text('utf-8'))
 old=json.loads((E/'previous_70_pilot_levels.json').read_text('utf-8'))
 used={geometry(l,False) for l in old['levels']+saved['levels']};started=time.time()
 with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
  for num in range(71+len(saved['levels']),101):
   budget=10 if num==95 else {96:11,97:11,98:12,99:12,100:14}[num]
   threshold=53+(num-95)*2.4;best=None
   cached=E/f'best_{num}_parallel.json'
   if cached.exists():
    data=json.loads(cached.read_text('utf-8'))
    if data['design'].get('author')=='boss100-aligned-gate-seeds-v3' and geometry(data['level'],False) not in used:best=(data['level'],data['design'])
   stride=args.workers*12
   for offset in range(args.offset,100000,stride):
    futures=[pool.submit(batch,(num,budget,used,offset+i*12)) for i in range(args.workers)]
    for future in concurrent.futures.as_completed(futures):
     out=future.result()
     if out and (best is None or out[1]['score']>best[1]['score']):
      best=out
      (E/f'best_{num}_parallel.json').write_text(json.dumps(dict(level=best[0],design=best[1]),ensure_ascii=False,indent=2)+'\n','utf-8')
      print('BEST',num,round(best[1]['score'],2),'domains',best[1]['canonicalDomains'],'extra',best[1]['minimumExtraDistance'],'seconds',int(time.time()-started),flush=True)
    if best and best[1]['score']>=threshold:break
    if (offset-args.offset)%(stride*8)==0:print('SEARCH',num,offset+stride,'seconds',int(time.time()-started),flush=True)
   if not best or best[1]['score']<threshold:raise RuntimeError(f'No certified candidate threshold at {num}')
   l,d=best;used.add(geometry(l,False));saved['levels'].append(l);saved['design'].append(d)
   target.write_text(json.dumps(saved,ensure_ascii=False,indent=2)+'\n','utf-8')
   print('ACCEPT',num,'moves',budget,'safe',d['canonicalSolutions'],'score',round(d['score'],2),flush=True)
   args.offset=0
 print('DONE',int(time.time()-started),flush=True)
if __name__=='__main__':main()
