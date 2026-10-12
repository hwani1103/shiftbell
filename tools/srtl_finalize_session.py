"""Run short post-hot-reload proofs, then always clear synthetic future alarms."""
import os, subprocess, sys, json
from pathlib import Path
from datetime import datetime

out=Path(os.environ['SHIFTBELL_AUDIT_OUT'])
results=[]
try:
    for script in ['srtl_onboarding_question_recheck','srtl_roster_last_day_recheck']:
        if datetime.now() >= datetime(2026,10,3,22,22,30):
            results.append({'step':script,'status':'skipped for lease cleanup'})
            continue
        with (out/(script+'.log')).open('w',encoding='utf8') as log:
            code=subprocess.call([sys.executable,'-u','tools/'+script+'.py'],stdout=log,stderr=subprocess.STDOUT)
        results.append({'step':script,'exit':code,'time':datetime.now().isoformat()})
        print(results[-1],flush=True)
finally:
    with (out/'cleanup.log').open('w',encoding='utf8') as log:
        code=subprocess.call([sys.executable,'-u','tools/srtl_remaining_cleanup.py'],stdout=log,stderr=subprocess.STDOUT)
    results.append({'step':'cleanup','exit':code,'time':datetime.now().isoformat()})
    (out/'finalize_results.json').write_text(json.dumps(results,indent=2),encoding='utf8')
    print(results[-1],flush=True)
