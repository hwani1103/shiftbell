"""Deterministic curation of solved candidates; no runtime or engine dependency."""
import json, copy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = ROOT / 'docs/next_version_27이후/game_implementation_v4'
ASSETS = ROOT / 'examples/sync_path_lab/assets'
pool = [json.loads(line) for name in ('candidates.jsonl', 'candidates_more.jsonl')
        for line in (EVIDENCE / name).read_text(encoding='utf-8-sig').splitlines()]
previous = json.loads((EVIDENCE / 'previous_12_levels.json').read_text(encoding='utf-8-sig'))
old_copy = json.loads((EVIDENCE / 'previous_12_copy.json').read_text(encoding='utf-8-sig'))
chosen, used = [], set()

def choose(target, units, extra=0, fixed=None):
    candidates = [c for c in pool if (c['seed'], c['attempt']) not in used
                  and c['metrics']['units'] in units
                  and c['metrics']['minimumExtraDistance'] >= extra]
    if fixed:
        c = next(c for c in candidates if (c['seed'], c['attempt']) == fixed)
    else:
        c = min(candidates, key=lambda c: (abs(c['metrics']['score']-target), c['metrics']['distinctSolutions'], c['attempt']))
    used.add((c['seed'], c['attempt']))
    chosen.append(copy.deepcopy(c))

# Five learning chapters, with multiple-unit mandatory detours in the last two.
for score, units, extra in [(5.6,[2],2),(5.9,[2,3],0),(6.3,[3],0),(6.7,[3],2),(7.0,[3],2),
                            (7.3,[3],2),(7.8,[3],2),(8.3,[3],2),(8.8,[3],2),(9.2,[3],2),
                            (9.6,[4],2),(10.1,[3,4],2),(10.6,[4],2),(11.1,[3,4],4),(11.7,[3,4],4),
                            (12.3,[4],4),(12.8,[3,4],4),(13.3,[4,5],2),(14.0,[4,5],4),(14.4,[3,4,5],4)]:
    choose(score, units, extra)
for fixed in [(271014,3563),(271014,6134),(271014,3958),(271013,14),(271014,389)]:
    choose(0,[3,4,5],fixed=fixed)

titles_ko=['첫 합류','같은 자리, 같은 순간','길이 겹쳐도','앞사람 따라가기','돌아가는 이유',
 '갈림길의 약속','한 칸의 여유','세 갈래 합류','먼저 비워 줄 자리','첫 번째 관문',
 '엇갈리는 출발','좁은 모퉁이','돌아오는 길','줄을 바꾸는 순간','두 번째 관문',
 '겹쳐진 약속','시간을 만드는 우회','교차로의 순서','한 번 더 양보','중간 시험',
 '얽힌 통로','두 개의 우회','합류의 조건','먼저 비우는 길','세 번째 관문',
 '이중 양보','긴 행렬','세 번의 우회','다섯 길의 합류','마지막 빈틈']
titles_en=['First meeting','Same place, same time','Paths may cross','Follow the leader','A reason to return',
 'Fork in the path','One cell of room','Three paths meet','Make room first','First checkpoint',
 'Staggered departures','A narrow corner','The return path','Changing the order','Second checkpoint',
 'Overlapping plans','A timely detour','Order at the crossing','Yield once more','Midway challenge',
 'Tangled corridors','Two detours','Conditions for joining','Clear the way','Third checkpoint',
 'Double courtesy','The long queue','Three detours','Five paths merge','The final opening']
chapter_ko=['1–5 · 튜토리얼 · 목표 난이도 2–3','6–10 · 경로 선택 · 목표 난이도 3–4',
 '11–15 · 시간차 조율 · 목표 난이도 4–5','16–20 · 복합 교차 · 목표 난이도 5–6',
 '21–25 · 연쇄 우회 · 목표 난이도 6–7','26–30 · 종합 도전 · 목표 난이도 7–8']
chapter_en=['1–5 · Tutorial · Target 2–3','6–10 · Route choices · Target 3–4',
 '11–15 · Timing · Target 4–5','16–20 · Crossings · Target 5–6',
 '21–25 · Linked detours · Target 6–7','26–30 · Final challenges · Target 7–8']

def compress(start, ends):
    result=[];prev=start;last_dir=None
    for end in ends:
        d=((end[0]>prev[0])-(end[0]<prev[0]),(end[1]>prev[1])-(end[1]<prev[1]))
        if d==last_dir:result[-1]=end
        else:result.append(end)
        prev=end;last_dir=d
    return result

def trim(level):
    cells=[(x,y) for y,row in enumerate(level['rows']) for x,c in enumerate(row) if c=='.']
    left=min(x for x,y in cells);top=min(y for x,y in cells)
    w=max(5,max(x for x,y in cells)-left+1);h=max(5,max(y for x,y in cells)-top+1)
    points={(x-left,y-top) for x,y in cells}
    level['rows']=[''.join('.' if (x,y) in points else '#' for x in range(w)) for y in range(h)]
    level['width']=w;level['height']=h
    for p in [level['goal']]+[u['start'] for u in level['units']]:p[0]-=left;p[1]-=top
    return left,top

levels=[];copies={};design=[]
for index, old in enumerate([1,2,3,10,7]):
    l=copy.deepcopy(previous['levels'][old-1]);l['id']=f'L{index+1:02}';l['revision']=1
    levels.append(l);copies[l['id']]=copy.deepcopy(old_copy[f'L{old:02}'])
    design.append({'id':l['id'],'source':f'previous-L{old:02}','targetDifficulty':'2–3','concept':titles_ko[index]})
for i,c in enumerate(chosen,6):
    l=c['level'];l['id']=f'L{i:02}';l['revision']=1
    dx,dy=trim(l)
    witness=c['metrics']['witness']
    for r in witness:
        r['endpoints']=[[x-dx,y-dy] for x,y in r['endpoints']]
        r['endpoints']=compress(next(u['start'] for u in l['units'] if u['id']==r['unitId']),r['endpoints'])
    levels.append(l)
    def reverses(route):
        p=next(u['start'] for u in l['units'] if u['id']==route['unitId']);dirs=[]
        for e in route['endpoints']:
            dirs.append(((e[0]>p[0])-(e[0]<p[0]),(e[1]>p[1])-(e[1]<p[1])));p=e
        return any(a[0]==-b[0] and a[1]==-b[1] for a,b in zip(dirs,dirs[1:]))
    focus=max(witness,key=lambda r:(reverses(r),len(r['endpoints'])))
    p=next(u['start'] for u in l['units'] if u['id']==focus['unitId']);ko=[];en=[]
    for e in focus['endpoints']:
        d=(e[0]-p[0],e[1]-p[1]);distance=abs(d[0])+abs(d[1])
        a,b=('오른쪽','right') if d[0]>0 else ('왼쪽','left') if d[0]<0 else ('아래','down') if d[1]>0 else ('위','up')
        ko.append(f'{a} {distance}칸');en.append(f'{distance} {b}');p=e
    m=c['metrics'];unit=focus['unitId']
    copies[l['id']]={'hintsKo':[
      '가까운 길만 고르면 만나는 곳이 있어요. 돌아가는 길을 찾아보세요.' if m['minimumExtraDistance'] else '길이 만나는 자리까지 각 Unit이 몇 칸 이동하는지 비교해 보세요.',
      f'{unit}의 경로부터 조정해 보세요. 나머지 Unit이 먼저 지나갈 공간을 만들 수 있어요.' if reverses(focus) else f'{unit}이 꺾는 통로부터 정한 뒤, 나머지 Unit의 합류 시점을 맞춰 보세요.',
      f'{unit}의 한 가지 안전한 경로: '+ ' → '.join(ko)+'. 나머지 길도 이 경로에 맞춰 보세요.'],
      'hintsEn':['The shortest routes collide. Find a useful detour.' if m['minimumExtraDistance'] else 'Count the cells each unit travels before the paths meet.',
       f'Plan {unit} first, then coordinate the others around its route.',f'One compatible route for {unit}: '+' → '.join(en)+'. Fit the other routes around it.']}
    design.append({'id':l['id'],'source':{'seed':c['seed'],'attempt':c['attempt']},
       'targetDifficulty':f'{(i-1)//5+2}–{(i-1)//5+3}','metrics':m,'witness':witness})
for i,l in enumerate(levels):
    item=copies[l['id']];item['titleKo']=titles_ko[i];item['titleEn']=titles_en[i]
    if i%5==0:item['chapterKo']=chapter_ko[i//5];item['chapterEn']=chapter_en[i//5]
pack={'schemaVersion':1,'ruleSetId':'constant-cell-speed-v2','packId':'dev-campaign-30','revision':1,'levels':levels}
for name,data in [('pilot_levels.json',pack),('pilot_copy.json',copies)]:
    (ASSETS/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
(EVIDENCE/'campaign_design.json').write_text(json.dumps({'humanPlaytest':'NOT_TESTED','difficulty':'relative authoring targets, not measured ratings','levels':design},ensure_ascii=False,indent=2)+'\n',encoding='utf8')
for l,d in zip(levels,design):
    print(l['id'],titles_en[int(l['id'][1:])-1],f"{l['width']}x{l['height']}",len(l['units']),'units',d.get('metrics',{}).get('score','tutorial'))
