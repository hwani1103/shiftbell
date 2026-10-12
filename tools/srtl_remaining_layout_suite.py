"""Sequential SRTL-only layout coverage; each script result remains separately visible."""
import os,sys,json,subprocess
from pathlib import Path
assert os.environ.get('SHIFTBELL_AUDIT_SERIAL','').startswith('localhost:')
base=Path('build/srtl_2026-10-03_ultra_final')
vm=(base/'vm.json').read_text(encoding='utf-8')
progress=base/'layout_suite_progress.json'
steps=json.loads(progress.read_text(encoding='utf-8')) if progress.exists() else []
def run(script, env, name, *args):
    selected=os.environ.get('SRTL_SUITE_STEPS')
    if selected and name not in selected.split(','):return
    out=Path(env['SHIFTBELL_AUDIT_OUT']);out.mkdir(parents=True,exist_ok=True)
    (out/'vm.json').write_text(vm,encoding='utf-8')
    with (out/(name+'.log')).open('w',encoding='utf-8') as log:
        code=subprocess.call([sys.executable,'-u','tools/'+script,*args],env=env,stdout=log,stderr=subprocess.STDOUT)
    steps.append({'out':str(out),'script':script,'name':name,'exit':code})
    (base/'layout_suite_progress.json').write_text(json.dumps(steps,indent=2),encoding='utf-8')
    print(name,code,flush=True)
    if code:raise RuntimeError(f'{script} failed; see {out/name}.log')
for scale in os.environ.get('SRTL_SUITE_SCALES','1.3,1.0,1.1,1.2').split(','):
    env={**os.environ,'SHIFTBELL_AUDIT_OUT':str(base/('other_'+scale)),
         'SRTL_SCALE':scale,'SRTL_SCALES':scale,'SRTL_AUDIT_SCALE':'1'}
    run('srtl_current_audit.py',env,'fixture','fixture')
    run('srtl_setup_layouts.py',env,'setup_choices')
    run('srtl_extra_layouts.py',env,'extra_dialogs')
    run('srtl_alarm_editor_layouts.py',env,'nested_alarm_editors')
    run('srtl_delete_dialog_layouts.py',env,'delete_confirmations')
    run('srtl_populated_schedules.py',env,'populated_timeline')
    run('srtl_timeline_positions.py',env,'timeline_scrolled')
    run('srtl_sleep_layouts.py',env,'populated_sleep')
    run('srtl_current_audit.py',env,'top_routes','screens')
print('Layout captures completed. Visual review and final error audit are separate.',flush=True)
