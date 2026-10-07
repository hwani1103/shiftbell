"""Read-only bounded observation of C10/C08 future natural arrivals."""
import time,json
import fsi_samsung_audit as a
cases=json.loads((a.OUT/'natural_cases_C.json').read_text())
remaining={k:v for k,v in cases.items() if k in ['10','30']}
end=time.monotonic()+2100
print('Read-only C observer started',flush=True)
while remaining and time.monotonic()<end:
 current=a.state()
 for minutes,case in list(remaining.items()):
  if current.get('currently_ringing_alarm_id')==str(case['id']) and int(current.get('currently_ringing_round','-1'))!=case['sourceRound'] and time.time()*1000>=case['target']:
   time.sleep(2)
   name='C_natural_'+minutes+'_round'+current['currently_ringing_round']
   a.shot(name)
   a.save(name+'_capture.json',{'case':case,'state':a.state(),'captured':time.time(),'status':'CAPTURED_PENDING_REVIEW'})
   remaining.pop(minutes)
   print('Captured '+name,flush=True)
 time.sleep(2)
print('C observer finished; pending='+str(list(remaining)),flush=True)
