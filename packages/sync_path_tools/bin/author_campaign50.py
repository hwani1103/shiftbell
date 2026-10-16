"""Bounded, deterministic level authoring. All chosen levels need Dart certification."""
import argparse
from collections import deque
from itertools import product
import json
import math
from pathlib import Path
import random

DIRS = [(1,0),(0,1),(-1,0),(0,-1)]

class Limit(Exception): pass

def connected(cells):
    unseen=set(cells); largest=set()
    while unseen:
        component={unseen.pop()}; queue=list(component)
        for x,y in queue:
            for dx,dy in DIRS:
                p=(x+dx,y+dy)
                if p in unseen: unseen.remove(p);component.add(p);queue.append(p)
        if len(component)>len(largest):largest=component
    return largest

def raw_weight(lengths, budget):
    coefficients=[1]+[0]*budget
    for distance in lengths:
        following=[0]*(budget+1)
        for used,value in enumerate(coefficients):
            if not value:continue
            for pieces in range(1,min(distance,budget-used)+1):
                following[used+pieces]+=value*math.comb(distance-1,pieces-1)
        coefficients=following
    return sum(coefficients)

def analyze(level, details=False):
    size=level['width']; goal=tuple(level['goal']);budget=level['maxCommands']
    floor={(x,y) for y,row in enumerate(level['rows']) for x,v in enumerate(row) if v=='.'}
    if connected(floor)!=floor:return None
    graph={}
    for cell in floor:
        targets=[]
        for dx,dy in DIRS:
            x,y=cell
            while (x+dx,y+dy) in floor:
                x+=dx;y+=dy; targets.append(((x,y),(dx,dy)))
                if (x,y)==goal:break
        graph[cell]=targets
    reverse={cell:[] for cell in floor}
    for cell,targets in graph.items():
        if cell==goal:continue
        for target,_ in targets:reverse[target].append(cell)
    turns={goal:0};queue=deque([goal])
    while queue:
        cell=queue.popleft()
        for target in reverse[cell]:
            if target not in turns:turns[target]=turns[cell]+1;queue.append(target)
    walking={goal:0};queue=deque([goal])
    while queue:
        x,y=queue.popleft()
        for dx,dy in DIRS:
            target=(x+dx,y+dy)
            if target in floor and target not in walking:
                walking[target]=walking[x,y]+1;queue.append(target)
    domains=[];raw_counts=[];nodes=0
    for unit in level['units']:
        start=tuple(unit['start']);routes=[];weight_sum=0
        def visit(cell,ends,path,lengths,last):
            nonlocal nodes,weight_sum
            nodes+=1
            if nodes>24000:raise Limit()
            if cell==goal:
                weight=raw_weight(lengths,budget);weight_sum+=weight
                if len(routes)>=55 or weight_sum>240:raise Limit()
                occupancy=0;edges=0
                for time,(x,y) in enumerate(path[:-1]):
                    occupancy |= 1 << (time*size*size+y*size+x)
                    ex,ey=path[time+1];minimum=min(y*size+x,ey*size+ex)
                    edge=minimum*2+int(y!=ey)
                    edges |= 1 << (time*size*size*2+edge)
                routes.append(dict(endpoints=ends,path=path,weight=weight,
                    length=len(path)-1,commands=len(ends),occupancy=occupancy,edges=edges))
                return
            if turns.get(cell,999)>budget-len(ends):return
            for target,direction in graph[cell]:
                if direction==last:continue # Equivalent straight splits only.
                x,y=cell;dx,dy=direction;trail=[]
                while (x,y)!=target:x+=dx;y+=dy;trail.append((x,y))
                visit(target,ends+[target],path+trail,lengths+[len(trail)],direction)
        try:visit(start,[],[start],[],None)
        except Limit:return None
        if not routes:return None
        domains.append(routes);raw_counts.append(weight_sum)
    n=len(domains);matrices={};conflicts=[0]*n;short_conflicts=[0]*n;pair_rates=[]
    minimum=[min(r['length'] for r in routes) for routes in domains]
    for i in range(n):
        for j in range(i+1,n):
            table=[];unsafe=0;short_unsafe=0
            for a in domains[i]:
                bits=0
                for bi,b in enumerate(domains[j]):
                    safe=not(a['occupancy']&b['occupancy'] or a['edges']&b['edges'])
                    if safe:bits |= 1<<bi
                    else:
                        unsafe+=1
                        if a['length']==minimum[i] and b['length']==minimum[j]:short_unsafe+=1
                table.append(bits)
            matrices[i,j]=table
            if unsafe:conflicts[i]+=1;conflicts[j]+=1
            if short_unsafe:short_conflicts[i]+=1;short_conflicts[j]+=1
            pair_rates.append(unsafe/(len(domains[i])*len(domains[j])))
    solutions=[];raw_solutions=0;search_nodes=0
    def search(chosen):
        nonlocal raw_solutions,search_nodes
        search_nodes+=1
        if search_nodes>50000:raise Limit()
        i=len(chosen)
        if i==n:
            raw_solutions+=math.prod(domains[k][r]['weight'] for k,r in enumerate(chosen))
            if len(solutions)>=500 or raw_solutions>2400:raise Limit()
            solutions.append(chosen);return
        allowed=(1<<len(domains[i]))-1
        for k,r in enumerate(chosen):allowed &= matrices[k,i][r]
        while allowed:
            bit=allowed & -allowed;allowed-=bit
            search(chosen+[bit.bit_length()-1])
    try:search([])
    except Limit:return None
    if not solutions:return None
    extras=[];detours=[];commands=[];reversals=[]
    best=None;best_key=None
    for solution in solutions:
        chosen=[domains[k][r] for k,r in enumerate(solution)]
        extra=sum(r['length']-minimum[k] for k,r in enumerate(chosen))
        detour=sum(r['length']>minimum[k] for k,r in enumerate(chosen))
        command=sum(r['commands'] for r in chosen)
        reverse_units=0
        for unit,r in zip(level['units'],chosen):
            p=tuple(unit['start']);directions=[]
            for e in r['endpoints']:
                directions.append(((e[0]>p[0])-(e[0]<p[0]),(e[1]>p[1])-(e[1]<p[1])));p=e
            reverse_units+=any(a==(-b[0],-b[1]) for a,b in zip(directions,directions[1:]))
        extras.append(extra);detours.append(detour);commands.append(command);reversals.append(reverse_units)
        key=(extra,command,max(r['length'] for r in chosen))
        if best_key is None or key<best_key:best_key=key;best=chosen
    space=math.prod(map(len,domains));bits=math.log2(space/len(solutions))
    score=n*1.0+bits*.65+min(extras)*.55+min(detours)*.9+min(commands)*.12
    mandatory=[set.intersection(*(set(r['path'][1:-1]) for r in d)) for d in domains]
    shared={c for i in range(n) for j in range(i+1,n) for c in mandatory[i]&mandatory[j] if walking[c]>=2}
    metrics=dict(units=n,temporalChoices={u['id']:len(d) for u,d in zip(level['units'],domains)},
        rawDomains=raw_counts,distinctSolutions=len(solutions),exactCommandSolutions=raw_solutions,
        minimumExtraDistance=min(extras),minimumDetouringUnits=min(detours),
        minimumReversingUnits=min(reversals),minimumTotalCommands=min(commands),
        shortestDistances=minimum,minimumCommands=[turns[tuple(u['start'])] for u in level['units']],
        shortestConflictParticipation=short_conflicts,conflictParticipation=conflicts,
        pairConflictRates=pair_rates,constraintBits=bits,score=score,
        sharedMandatoryCells=[list(c) for c in sorted(shared)],walkableCells=len(floor),
        witness=[dict(unitId=u['id'],endpoints=[list(e) for e in r['endpoints']]) for u,r in zip(level['units'],best)])
    return (metrics, domains, solutions) if details else metrics

def layout(rng,size,family):
    if family=='maze':
        cells={(x,y) for y in range(0,size,2) for x in range(0,size,2)}
        first=rng.choice(sorted(cells));seen={first};open={first};stack=[first]
        while stack:
            x,y=stack[-1];choices=[(x+2*dx,y+2*dy) for dx,dy in DIRS if (x+2*dx,y+2*dy) in cells-seen]
            if not choices:stack.pop();continue
            p=rng.choice(choices);seen.add(p);open.add(p);open.add(((x+p[0])//2,(y+p[1])//2));stack.append(p)
        links=[(x,y) for y in range(size) for x in range(size) if (x%2)!=(y%2) and (x,y) not in open]
        rng.shuffle(links);open.update(links[:rng.randint(1,3)])
        return open
    density=rng.uniform(.48,.67)
    cells={(x,y) for y in range(size) for x in range(size) if rng.random()<density}
    return connected(cells)

def main():
    p=argparse.ArgumentParser();p.add_argument('--seed',type=int,default=501014);p.add_argument('--attempts',type=int,default=16000);p.add_argument('--out',type=Path,required=True);p.add_argument('--mode',choices=['initial','multi'],default='multi')
    args=p.parse_args();rng=random.Random(args.seed);kept=0;stats={2:0,3:0,4:0}
    args.out.parent.mkdir(parents=True,exist_ok=True)
    with args.out.open('w',encoding='utf-8') as sink:
        for attempt in range(args.attempts):
            n=([2,3,4,4] if args.mode=='initial' else [3,4,4,4])[attempt%4]
            size=rng.choice([5,5,6,7] if n==2 else [5,6,6,7] if n==3 else [6,7,7])
            family=rng.choice(['maze','rooms','rooms']) if size%2 else 'rooms'
            floor=layout(rng,size,family)
            if len(floor)<(13 if n==2 else 18 if n==3 else 23):continue
            degree=lambda c:sum((c[0]+dx,c[1]+dy) in floor for dx,dy in DIRS)
            goals=sorted(c for c in floor if degree(c)>=(2 if args.mode=='initial' else 1))
            if not goals:continue
            goal=rng.choice(goals)
            starts=[c for c in sorted(floor) if abs(c[0]-goal[0])+abs(c[1]-goal[1])>=3]
            if len(starts)<n:continue
            # Equal shortest travel distances expose meaningful merge conflicts.
            distances={goal:0};queue=deque([goal])
            while queue:
                x,y=queue.popleft()
                for dx,dy in DIRS:
                    c=(x+dx,y+dy)
                    if c in floor and c not in distances:
                        distances[c]=distances[x,y]+1;queue.append(c)
            groups={}
            for c in starts:groups.setdefault(distances[c],[]).append(c)
            eligible=[group for distance,group in groups.items() if len(group)>=n and distance>=4]
            if args.mode=='multi' and eligible and rng.random()<.8:starts=rng.choice(eligible)
            rng.shuffle(starts);starts=starts[:n]
            budget=rng.choice([3,4,4,5] if n==2 else [4,4,5,5,6])
            if budget>5:continue
            level=dict(id=f'S{args.seed}-{attempt}',revision=1,width=size,height=size,
                rows=[''.join('.' if (x,y) in floor else '#' for x in range(size)) for y in range(size)],
                goal=list(goal),units=[dict(id=chr(65+i),start=list(c)) for i,c in enumerate(starts)],
                maxCommands=budget,requiredMechanics=['straight-motion','absorbing-shared-goal'])
            m=analyze(level)
            if not m or min(m['minimumCommands'])<2 or min(m['shortestDistances'])<4:continue
            if min(m['conflictParticipation'])<1 or m['constraintBits']<.5:continue
            if n>=3 and ((min(m['shortestConflictParticipation'])<1 if args.mode=='initial' else sum(x>0 for x in m['shortestConflictParticipation'])<2) or m['minimumExtraDistance']<2):continue
            entry=dict(seed=args.seed,attempt=attempt,family=family,level=level,metrics=m)
            sink.write(json.dumps(entry,ensure_ascii=False)+'\n');sink.flush();kept+=1;stats[n]+=1
            if kept%20==0:print('kept',kept,'attempt',attempt,'units',stats,'last score',round(m['score'],2),flush=True)
        print('DONE',args.attempts,'kept',kept,stats,flush=True)
if __name__=='__main__':main()
