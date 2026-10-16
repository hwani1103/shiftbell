"""Deterministic boss search with deeper goal selection; v3 seeds stay separate."""
import random
from author_finale100 import design_candidate

def batch(args):
 num,budget,used,start=args;best=None
 for attempt in range(start,start+12):
  seed=49100000+num*100000+attempt
  out=design_candidate(random.Random(seed),budget,8 if num==100 else 7,used,num,boss_geometry='wide')
  if out and (best is None or out[1]['score']>best[1]['score']):
   out[1].update(seed=seed,attempts=attempt+1,author='boss100-wide-combinations-v6')
   best=out
 return best
