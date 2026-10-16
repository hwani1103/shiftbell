"""Freeze boss selection against the requested move/detour progression."""
import json
from author_finale100 import E

target=E/'finale_candidates.json';saved=json.loads(target.read_text('utf-8'))
assert len(saved['levels']) in (24,30)
saved['levels']=saved['levels'][:24];saved['design']=saved['design'][:24]
chosen=[]
for n in range(95,101):
 source='boss100_refined.json' if n==100 else f'best_{n}_parallel.json'
 candidate=json.loads((E/source).read_text('utf-8'));l,d=candidate['level'],candidate['design']
 assert d['minimumRequiredMaxCommands']==l['maxCommands']
 assert d['minimumTotalCommands']>={95:38,96:41,97:44,98:46,99:47,100:56}[n]
 assert d['minimumExtraDistance']>={95:20,96:20,97:24,98:20,99:20,100:24}[n]
 assert len(l['gates'])==2 and len(l.get('portals',[]))<=2
 saved['levels'].append(l);saved['design'].append(d)
 chosen.append(dict(source=source,sourceId=d['id'],minimumTotalCommands=d['minimumTotalCommands'],minimumExtraDistance=d['minimumExtraDistance'],score=d['score']))
target.write_text(json.dumps(saved,ensure_ascii=False,indent=2)+'\n','utf-8')
(E/'boss_curation.json').write_text(json.dumps(dict(
 selection='Mandatory move budget, mandatory total commands and mandatory detour; entropy is a secondary heuristic, not human difficulty.',
 earlierSearchThresholds='Exploration targets only. Final curation uses the requested move/detour progression instead of treating an entropy score as a human-difficulty certificate.',
 finalLevel=dict(board=[8,8],allFourBallsRequireCommands=14,totalCommands=56,mandatoryExtraDistance=24,
  maximumExtraDistanceAmongCollisionSafeBasePlans=24,canonicalSolutions=1),
 candidates=chosen,humanPlaytest='NOT_TESTED'),ensure_ascii=False,indent=2)+'\n','utf-8')
print('Frozen bosses. Final level forces all four balls to use 14 commands and the full 24-cell detour.')
