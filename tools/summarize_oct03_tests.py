"""Summarize runner evidence; distinguish initial harness failures and reruns."""
import json
import pathlib
import xml.etree.ElementTree as ET
from collections import Counter

root=pathlib.Path(__file__).resolve().parents[1]
out=root/'build/local_audit_2026-10-03'
latest={}
runs=[]
for name,config in [('flutter_all.jsonl','default'),('remaining_targeted.jsonl','default'),
                    ('onboarding_regression.jsonl','default'),('compact.jsonl','compact'),
                    ('storage_date_move_fixed.jsonl','default')]:
    path=out/name
    tests={}
    results=[]
    finished=None
    raw=path.read_bytes()
    decoded=raw.decode('utf-16' if raw.startswith(b'\xff\xfe') else 'utf-8-sig')
    for line in decoded.splitlines():
        try:event=json.loads(line)
        except (json.JSONDecodeError,ValueError):continue
        if event.get('type')=='testStart':tests[event['test']['id']]=event['test']
        elif event.get('type')=='testDone' and not event.get('hidden',False):
            test=tests[event['testID']]
            # Use source URL where available. For widget tests, root_url identifies the suite.
            source=test.get('root_url') or test.get('url') or ''
            key=(config,source,test['name'])
            record={'config':config,'source':source.replace(root.as_posix()+'/', ''),
                    'name':test['name'],'result':event['result'],'skipped':event.get('skipped',False),'log':name}
            latest[key]=record
            results.append(record)
        elif event.get('type')=='done':finished=event
    runs.append({'log':name,'counts':dict(Counter(r['result'] for r in results)),
                 'complete':finished is not None,'success':finished.get('success') if finished else None,
                 'elapsed_ms':finished.get('time') if finished else None})
android=[ET.parse(p).getroot() for p in (root/'build/app/test-results/testDevDebugUnitTest').glob('*.xml')]
summary={'flutter_runs':runs,
         'flutter_final_unique_by_config':{c:dict(Counter(r['result'] for r in latest.values() if r['config']==c)) for c in ['default','compact']},
         'android':{'suites':len(android),**{key:sum(int(s.get(key,0)) for s in android) for key in ['tests','failures','errors','skipped']}},
         'remaining_failures':[r for r in latest.values() if r['result']!='success' and not r['skipped']]}
(out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
(out/'flutter_final_cases.json').write_text(json.dumps(list(latest.values()),ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(summary,ensure_ascii=False,indent=2))
