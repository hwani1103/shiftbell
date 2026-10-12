"""Only outstanding Fold8Ultra layouts; sequential UI operations and resumable stages."""
import os,sys,subprocess,json,time
from pathlib import Path
assert os.environ.get('SHIFTBELL_AUDIT_SERIAL','').startswith('localhost:')
out=Path(os.environ['SHIFTBELL_AUDIT_OUT']);out.mkdir(parents=True,exist_ok=True)
steps=[
 ('fixture','srtl_current_audit.py',['fixture'],''),
 ('custom_seed','srtl_extra_layouts.py',[],''),
 ('populated_schedules','srtl_populated_schedules.py',[],'1.0,1.1,1.2,1.3'),
 ('timeline_positions','srtl_timeline_positions.py',[],'1.0,1.1,1.2,1.3'),
 ('sleep','srtl_sleep_layouts.py',[],'1.0,1.1,1.2,1.3'),
 ('nested_alarms','srtl_alarm_editor_layouts.py',[],'1.0,1.1,1.2,1.3'),
 ('delete_dialogs','srtl_delete_dialog_layouts.py',[],'1.0,1.1,1.2,1.3'),
 ('roster_details','srtl_roster_details.py',[],'1.0,1.3'),
 ('setup_recheck','srtl_setup_layouts.py',[],'1.0,1.3'),
 ('onboarding_label','srtl_onboarding_label_recheck.py',[],'1.0,1.1,1.2,1.3'),
 ('remaining_routes','srtl_current_audit.py',['screens'],'1.0,1.1,1.2,1.3'),
]
selected=os.environ.get('SRTL_REMAINING_STEPS')
progress=out/'progress.json';results=json.loads(progress.read_text(encoding='utf8')) if progress.exists() else []
for name,script,args,sweep in steps:
 if selected and name not in selected.split(','):continue
 env={**os.environ,'SRTL_SCALE':'1.3','SRTL_SCALES':'1.3','SRTL_INSPECT_SCALES':sweep,'SRTL_EXTRA_GROUPS':'seed_only','SRTL_DETAIL_SCROLL_ONLY':'0'}
 started=time.time();print('START',name,time.strftime('%H:%M:%S'),flush=True)
 with (out/(name+'.log')).open('w',encoding='utf8') as f:
  code=subprocess.call([sys.executable,'-u','tools/'+script,*args],env=env,stdout=f,stderr=subprocess.STDOUT)
 result={'step':name,'exit':code,'elapsed_seconds':round(time.time()-started,1),'completed':time.strftime('%Y-%m-%d %H:%M:%S')}
 results.append(result);progress.write_text(json.dumps(results,indent=2),encoding='utf8');print(result,flush=True)
 if code:
  print((out/(name+'.log')).read_text(encoding='utf8')[-4500:],flush=True)
  raise SystemExit(code)
print('All selected device stages complete; visual review remains separate.',flush=True)
