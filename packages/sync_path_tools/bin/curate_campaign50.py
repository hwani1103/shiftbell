"""Curate fifty fresh puzzles with measurable, gradual authoring constraints."""
import copy
import importlib.util
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
EVIDENCE=ROOT/'docs/next_version_27이후/game_implementation_v6'
ASSETS=ROOT/'examples/sync_path_lab/assets'
spec=importlib.util.spec_from_file_location('author',Path(__file__).with_name('author_campaign50.py'))
author=importlib.util.module_from_spec(spec);spec.loader.exec_module(author)

from campaign_geometry import geometry

pool=[json.loads(line) for name in ['candidates50.jsonl','candidates50_multi.jsonl']
      for line in (EVIDENCE/name).read_text(encoding='utf-8-sig').splitlines()]
old=json.loads((EVIDENCE/'previous_30_pilot_levels.json').read_text(encoding='utf-8-sig'))
old_keys={geometry(l) for l in old['levels']}
seen=set();floors=set();chosen=[];last_score=0

def add(candidate,concept):
    global last_score
    candidate=copy.deepcopy(candidate);level=candidate['level'];m=candidate['metrics']
    assert geometry(level) not in seen
    seen.add(geometry(level));floors.add(geometry(level,False));last_score=m['score']
    chosen.append(candidate);candidate['concept']=concept

first=copy.deepcopy(old['levels'][0]);first['id']='tutorial-safe';first['maxCommands']=2
add(dict(level=first,metrics=author.analyze(first),family='handcrafted',seed=None,attempt=None),'Separated routes; every legal complete plan is safe')
second=dict(id='tutorial-crossing',revision=1,width=5,height=5,rows=['.....']*5,goal=[2,2],
    units=[dict(id='A',start=[0,0]),dict(id='B',start=[4,0])],maxCommands=2,requiredMechanics=['straight-motion','absorbing-shared-goal'])
add(dict(level=second,metrics=author.analyze(second),family='handcrafted',seed=None,attempt=None),'Obvious unsafe top meeting; three safe shortest combinations')
third=dict(id='tutorial-branch',revision=1,width=5,height=5,rows=['.....','.###.','.....','##.#.','.....'],goal=[2,4],
    units=[dict(id='A',start=[0,0]),dict(id='B',start=[4,0])],maxCommands=3,requiredMechanics=['straight-motion','absorbing-shared-goal'])
add(dict(level=third,metrics=author.analyze(third),family='handcrafted',seed=None,attempt=None),'Keep separate outer paths; crossing route exists without needing a time detour')

def choose(number,target,n,extra=2,detours=1,size=None,shared=0,short_all=False,max_extra=None,max_detours=None):
    candidates=[]
    for c in pool:
        l=c['level'];m=c['metrics']
        if l['maxCommands']>5:continue
        if m['units']!=n or geometry(l) in seen or geometry(l) in old_keys:continue
        if geometry(l,False) in floors:continue
        if number>=5 and m['score']>last_score+.95:continue
        if max_extra is not None and m['minimumExtraDistance']>max_extra:continue
        if max_detours is not None and m['minimumDetouringUnits']>max_detours:continue
        if m['score']<last_score+.02 or m['minimumExtraDistance']<extra or m['minimumDetouringUnits']<detours:continue
        if min(m['minimumCommands'])<2 or min(m['shortestDistances'])<4:continue
        if size is not None and l['width']!=size:continue
        if len(m['sharedMandatoryCells'])<shared:continue
        if short_all and min(m['shortestConflictParticipation'])<1:continue
        if min(m['conflictParticipation'])<1:continue
        if n>=3 and m['distinctSolutions']>(64 if number==30 else 32):continue
        candidates.append(c)
    if not candidates:raise RuntimeError(f'No candidate for {number}: target {target}, previous {last_score}, size {size}, extra {extra}')
    # Keep difficulty close to the target, then prefer clean/compact finite domains.
    c=min(candidates,key=lambda c:(abs(c['metrics']['score']-target),
        max(c['metrics']['temporalChoices'].values()),c['metrics']['distinctSolutions'],c['attempt']))
    add(c,f'{n}-ball coordination; required extra {c["metrics"]["minimumExtraDistance"]} cells')

choose(4,5.4,2,size=5)
choose(5,5.8,2,size=5)
for number in range(6,15):
    choose(number,6.0+(number-6)*.27,2,size={6:5,7:6,8:5,10:6,11:5,12:6}.get(number))
for number in range(15,30):
    target=8.6+(number-15)*.49
    choose(number,target,3,extra=2 if number<20 else 4 if number<25 else 6,
        detours=1 if number<25 else 2,
        size={15:6,20:6,23:7,27:5,29:7}.get(number),
        short_all=number>=25)
for number in range(30,51):
    target=16.1+(number-30)*.49
    choose(number,target,4,extra=4 if number<35 else 6 if number<40 else 8 if number<45 else 12,
        detours=2 if number<45 else 3,
        size={30:6,33:7,35:6,40:7,43:6,45:7,48:7,50:7}.get(number),
        short_all=True,max_extra=6 if number==30 else None,max_detours=2 if number==30 else None)

ko=['첫 출발','같은 자리, 같은 순간','길을 나눠요','한 번의 우회','한 칸의 여유',
'두 갈래 통로','모퉁이의 약속','돌아서 합류','먼저 비우기','첫 교차로',
'작은 지도, 좁은 틈','길이 만드는 시간','엇갈린 입구','두 길의 시험','세 번째 공',
'세 갈래 순서','양보할 자리','작은 방의 세 길','다른 길, 같은 순간','꺾어서 합류',
'통로의 순서','되돌아오는 시간','좁은 가운데','돌아가는 역할','세 길의 약속',
'두 공의 우회','작은 지도의 큰 고민','엇갈린 순환로','세 공의 관문','네 번째 공',
'네 갈래 시작','한꺼번에 모이지 않게','빈자리 만들기','모퉁이 네 개','연쇄 양보',
'합류의 조건','네 공의 약속','한 길이 바뀌면','얽힌 입구','통로의 약속',
'시간을 나누는 방','지나간 자리','모두의 우회','좁은 문 앞에서','네 길의 균형',
'멀리 돌아가는 이유','마지막 교차로','서로 비우는 시간','딱 맞는 순서','함께, 마지막 도착']
en=['First departure','Same place, same time','Separate paths','One useful detour','A little room',
'Two corridors','A corner promise','Go around to join','Make room first','First crossing',
'Small map, narrow gap','Time made by paths','Staggered entrances','Two-path test','The third ball',
'Three-path order','Room to yield','Three paths in a small room','Different paths, same moment','Turn to join',
'Corridor order','Time to return','The narrow middle','A role for detours','Three-path promise',
'Two balls detour','Small map, big decisions','A winding circuit','Three-ball checkpoint','The fourth ball',
'Four departures','Avoid a crowd','Create an opening','Four corners','Linked courtesy',
'Conditions for joining','Four-ball promise','Change one path','Tangled entrances','Corridor promise',
'A room for timing','A cleared cell','Shared detours','Before the narrow gate','Four-path balance',
'A longer way for a reason','Final crossing','Time to make room','The right order','Arrive together']
chapters_ko=['첫 출발과 우회','두 길의 합류','세 번째 공으로','세 길의 조율','서로 시간을 만들기',
'네 번째 공으로','네 길의 합류','연쇄 양보','함께 만드는 빈틈','마지막 도전']
chapters_en=['First paths and detours','Joining two paths','Meet the third ball','Coordinate three paths','Create room together',
'Meet the fourth ball','Joining four paths','Linked courtesy','Create an opening','Final challenges']

def directions(start,endpoints,korean):
    p=start;parts=[]
    for e in endpoints:
        dx=e[0]-p[0];dy=e[1]-p[1];distance=abs(dx)+abs(dy)
        direction=('오른쪽' if dx>0 else '왼쪽' if dx<0 else '아래' if dy>0 else '위') if korean else ('right' if dx>0 else 'left' if dx<0 else 'down' if dy>0 else 'up')
        parts.append(f'{direction} {distance}칸' if korean else f'{distance} {direction}');p=e
    return ' → '.join(parts)

levels=[];copies={};design=[]
for i,c in enumerate(chosen,1):
    l=c['level'];m=c['metrics'];l['id']=f'L{i:02}';l['revision']=1;levels.append(l)
    routes=m['witness']
    # Choose the unit with the largest demonstrated time detour.
    def extra(j):
        p=l['units'][j]['start'];distance=0
        for e in routes[j]['endpoints']:distance+=abs(e[0]-p[0])+abs(e[1]-p[1]);p=e
        return distance-m['shortestDistances'][j],len(routes[j]['endpoints'])
    focus=max(range(len(routes)),key=extra);unit=routes[focus]['unitId']
    first_hint='공마다 따로 이어진 길을 따라 도착점까지 보내 보세요.' if i==1 else '윗길에서 동시에 만나지 않도록 서로 다른 통로를 골라 보세요.' if i==2 else '가장자리 길을 먼저 찾아보세요. 돌아서 시간을 만들 필요는 없어요.' if i==3 else '가까운 길만 고르면 충돌해요. 이동한 칸 수로 합류 시간을 비교해 보세요.'
    hint2='밝게 표시된 칸을 탭하고, 경로가 완성되면 다음 공을 골라 주세요.' if i==1 else f'{unit}의 길부터 조정해 보세요. '+('한 번 돌아가면 다른 공이 먼저 지나갈 시간을 만들 수 있어요.' if m['minimumExtraDistance'] else '다른 공과 만나는 통로를 바꿀 수 있어요.')
    answer_ko='\n'.join(f"{r['unitId']}: {directions(l['units'][j]['start'],r['endpoints'],True)}" for j,r in enumerate(routes))
    answer_en='\n'.join(f"{r['unitId']}: {directions(l['units'][j]['start'],r['endpoints'],False)}" for j,r in enumerate(routes))
    copies[l['id']]=dict(titleKo=ko[i-1],titleEn=en[i-1],hintsKo=[first_hint,hint2,'한 가지 안전한 경로예요.\n'+answer_ko],
        hintsEn=['Follow the separate corridors.' if i==1 else 'Count the cells traveled before the paths join. A detour can create room.',f'Adjust {unit} first, then fit the other routes around it.','One safe complete plan:\n'+answer_en])
    if (i-1)%5==0:
        chapter=(i-1)//5
        copies[l['id']]['chapterKo']=f'{chapter*5+1}–{chapter*5+5} · {chapters_ko[chapter]}'
        copies[l['id']]['chapterEn']=f'{chapter*5+1}–{chapter*5+5} · {chapters_en[chapter]}'
    design.append(dict(id=l['id'],source=dict(seed=c.get('seed'),attempt=c.get('attempt'),family=c['family']),
        concept=c['concept'],authoringDifficulty=m['score'],metrics=m,witness=routes))
pack=dict(schemaVersion=1,ruleSetId='constant-cell-speed-v2',packId='dev-campaign-50',revision=1,levels=levels)
for name,data in [('pilot_levels.json',pack),('pilot_copy.json',copies)]:
    (ASSETS/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(EVIDENCE/'campaign_design.json').write_text(json.dumps(dict(humanPlaytest='NOT_TESTED',
    difficulty='Strictly increasing analytical authoring score; human difficulty still requires playtesting',
    candidatesReviewed=len(pool),levels=design),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for l,d in zip(levels,design):
    m=d['metrics'];print(l['id'],l['width'],len(l['units']),round(m['score'],2),'extra',m['minimumExtraDistance'],'detours',m['minimumDetouringUnits'],'solutions',m['distinctSolutions'])
