"""Read-only acceptance checks for the fifty-level pack and its certificates."""
import json
from pathlib import Path
from collections import Counter
ROOT=Path(__file__).resolve().parents[3]
EVIDENCE=ROOT/'docs/next_version_27이후/game_implementation_v6'
pack=json.loads((ROOT/'examples/sync_path_lab/assets/pilot_levels.json').read_text(encoding='utf-8'))
design=json.loads((EVIDENCE/'campaign_design.json').read_text(encoding='utf-8'))
proof=json.loads((EVIDENCE/'level_verification.json').read_text(encoding='utf-8'))
from campaign_geometry import geometry
keys=set();floors=set()
assert len(pack['levels'])==len(design['levels'])==len(proof['levels'])==50
for number,(level,entry,report) in enumerate(zip(pack['levels'],design['levels'],proof['levels']),1):
    m=entry['metrics'];expected=2 if number<15 else 3 if number<30 else 4
    assert len(level['units'])==expected
    assert level['width']==level['height'] and level['width'] in [5,6,7]
    assert 1<=level['maxCommands']<=5
    assert all(abs(u['start'][0]-level['goal'][0])+abs(u['start'][1]-level['goal'][1])>=3 for u in level['units'])
    assert report['distinctSolutionCount']==m['distinctSolutions']
    assert int(report['rawSolutionCount'])==m['exactCommandSolutions']
    assert geometry(level) not in keys;keys.add(geometry(level));floors.add(geometry(level,False))
    if number>=4:assert m['minimumExtraDistance']>=2 and min(m['minimumCommands'])>=2 and min(m['shortestDistances'])>=4
    if number>=15:assert min(m['conflictParticipation'])>0
    if number>=30:assert min(m['shortestConflictParticipation'])>0
    if number>=45:assert m['minimumDetouringUnits']>=3 and m['minimumExtraDistance']>=12
assert len(floors)==50
scores=[e['metrics']['score'] for e in design['levels']]
assert all(a<b for a,b in zip(scores,scores[1:]))
assert all(b-a<=.95 for a,b in zip(scores[3:],scores[4:]))
assert design['levels'][0]['metrics']['distinctSolutions']==1 and design['levels'][0]['metrics']['constraintBits']==0
for i in [1,2]:assert design['levels'][i]['metrics']['minimumExtraDistance']==0 and design['levels'][i]['metrics']['constraintBits']>0
for i in [3,4]:assert design['levels'][i]['metrics']['minimumExtraDistance']==2 and design['levels'][i]['metrics']['minimumDetouringUnits']==1
summary=dict(levels=50,boards=dict(Counter(str(l['width'])+'x'+str(l['height']) for l in pack['levels'])),
    units=dict(Counter(len(l['units']) for l in pack['levels'])),distinctPuzzles=len(keys),distinctFloorLayouts=len(floors),
    scoresStrictlyIncrease=True,maxPostTutorialScoreStep=max(b-a for a,b in zip(scores[3:],scores[4:])),
    minimumStartGoalManhattan=3,allAuthoringSolutionCountsMatchDart=True,pairComparisons=proof['pairComparisons'],
    distinctSafeAssignments=proof['distinctSafeAssignments'],humanPlaytest='NOT_TESTED',chapters=[dict(levels=f'{i+1}-{i+5}',
      meanScore=sum(scores[i:i+5])/5,minimumExtraDistance=min(e['metrics']['minimumExtraDistance'] for e in design['levels'][i:i+5])) for i in range(0,50,5)])
(EVIDENCE/'quality_checks.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
print(json.dumps(summary))
