"""Read-only campaign quality checks; writes authoring evidence only."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[3]
folder = root / 'docs/next_version_27이후/game_implementation_v4'
pack = json.loads((root / 'examples/sync_path_lab/assets/pilot_levels.json').read_text(encoding='utf8'))
design = json.loads((folder / 'campaign_design.json').read_text(encoding='utf8'))
seen = {}
for level in pack['levels']:
    variants=[]
    floor=[(x,y) for y,row in enumerate(level['rows']) for x,v in enumerate(row) if v=='.']
    for swap in (False,True):
        for sx in (-1,1):
            for sy in (-1,1):
                def transform(c):
                    x,y=c
                    if swap:x,y=y,x
                    return sx*x,sy*y
                transformed=list(map(transform,floor))
                left=min(x for x,y in transformed);top=min(y for x,y in transformed)
                def norm(c):
                    x,y=transform(c)
                    return x-left,y-top
                variants.append(str((sorted(norm(c) for c in floor),norm(level['goal']),
                    sorted(norm(u['start']) for u in level['units']),level['maxCommands'])))
    key=min(variants)
    assert key not in seen,(level['id'],seen.get(key))
    seen[key]=level['id']
summary={'distinctUnderRotationReflectionTranslation':len(seen),'chapters':[]}
for chapter in range(6):
    entries=design['levels'][chapter*5:chapter*5+5]
    scores=[e['metrics']['score'] for e in entries if 'metrics' in e]
    summary['chapters'].append({'levels':f'{chapter*5+1}-{chapter*5+5}',
        'target':f'{chapter+2}-{chapter+3}','meanHeuristic':sum(scores)/len(scores) if scores else None,
        'notHumanCalibrated':True})
means=[c['meanHeuristic'] for c in summary['chapters'][1:]]
assert all(a<b for a,b in zip(means,means[1:]))
(folder/'curation_checks.json').write_text(json.dumps(summary,indent=2),encoding='utf8')
print('PASS: 30 distinct layouts, chapter heuristic means increase:',means)
