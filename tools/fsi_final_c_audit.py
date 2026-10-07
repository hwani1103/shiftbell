"""Read-only final restoration audit; explicit USB Samsung, dev DB only."""
import json,re,time
from pathlib import Path
import fsi_samsung_audit as a
from datetime import datetime
base=json.loads((a.OUT/'baseline_device.json').read_text(encoding='utf-8'))
initial=json.loads((a.OUT/'initial_tables.json').read_text(encoding='utf-8'))
rows=a.db_snapshot('C_final_rows')
assert not rows['alarms'],rows['alarms']
assert a.state().get('currently_ringing_alarm_id') is None
unchanged={}
for name in ['alarm_history','alarm_creation_log','alarm_types']:
 after={r['id']:r for r in rows[name]}
 changed=[r['id'] for r in initial[name] if after.get(r['id'])!=r]
 assert not changed,(name,changed)
 unchanged[name]=len(initial[name])
commands={'zone':['getprop','persist.sys.timezone'],'auto_time':['settings','get','global','auto_time'],'auto_zone':['settings','get','global','auto_time_zone'],'stay':['settings','get','global','stay_on_while_plugged_in'],'font_scale':['settings','get','system','font_scale'],'screen_timeout':['settings','get','system','screen_off_timeout'],'locales':['cmd','locale','get-app-locales',a.PACKAGE],'uimode':['cmd','uimode','night'],'accessibility':['settings','get','secure','enabled_accessibility_services']}
settings={k:a.shell(*v) for k,v in commands.items()}
for key,value in settings.items():assert value==base[key],(key,base[key],value)
power=a.shell('dumpsys','power');policy=a.shell('dumpsys','window','policy')
assert 'mStayOn=true' in power and 'mWakefulness=Awake' in power
assert 'showing=false' in policy
alarms=a.shell('dumpsys','alarm');notifications=a.shell('dumpsys','notification')
def wakes(s,pkg):
 lines=s.splitlines();result=[]
 for i,l in enumerate(lines):
  if 'RTC_WAKEUP #' in l and (' '+pkg+'}') in l:
   tag=lines[i+1].strip().split('/')[-1]
   result.append({'receiver':tag,'epoch':int(re.search(r'origWhen (\d+)',l).group(1))})
 return result
prod=lambda s:sorted([r for r in wakes(s,'com.hwani1103.shiftbell') if r['receiver'] in ['.CustomAlarmReceiver','.AlarmGuardReceiver']],key=lambda r:r['epoch'])
assert prod(alarms)==prod(base['alarmmanager'])
assert not [r for r in wakes(alarms,a.PACKAGE) if 'CustomAlarmReceiver' in r['receiver']]
lines=alarms.splitlines()
for i,line in enumerate(lines[:-1]):
 if re.match(r'\s+(?:RTC|ELAPSED)[^#]* #\d+: Alarm',line) and (' '+a.PACKAGE+'}') in line:
  assert 'RING_TIMEOUT' not in lines[i+1],lines[i+1]
snoozed=notifications.split('  Snoozed notifications:',1)[1].split('  SCPM Version Info:',1)[0]
assert a.PACKAGE not in snoozed
import sqlite3
with sqlite3.connect(a.OUT/'C_final_rows_db'/'shiftbell.db') as connection:
 triggers=connection.execute("SELECT name FROM sqlite_master WHERE type='trigger'").fetchall()
 assert not triggers,triggers
active=notifications.split('Snoozed notifications:')[0]
assert not re.search(r'NotificationRecord\([^\n]*pkg='+re.escape(a.PACKAGE)+r'[^\n]* id=7777 ',active)
a.save('C_final_restoration.json',{'checkedAt':datetime.now().isoformat(),'settings':settings,'baselineRowsPreserved':unchanged,'devAlarms':0,'activeRing':None,'awakeAndUnlocked':True,'prodReservationsUnchanged':prod(alarms),'status':'PASS'})
a.shot('C_final_restored')
print('Final restoration PASS: original rows/settings/prod alarms preserved; dev alarms0; awake/unlocked',flush=True)
