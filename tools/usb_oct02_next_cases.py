import sys,json
from usb_audit_device import evaluate,OUT,compare_os

stage=sys.argv[1]
if stage=='prepare':
 kind=sys.argv[2] if len(sys.argv)>2 else 'custom'
 assert kind in ['custom','snoozed']
 ident=evaluate('next_extra_create','providers/alarm_provider.dart',"""(() async {
 final d=await DatabaseService.instance.database;final ids=(await d.query('alarms')).map((r)=>r['id']).toSet();
 final now=DateTime.now();final at=now.add(const Duration(hours:1));final n=AlarmNotifier();
 try{await n.addAlarm(Alarm(time:'${at.hour.toString().padLeft(2,'0')}:${at.minute.toString().padLeft(2,'0')}',date:at,type:'custom',alarmTypeId:1,presetSlot:4,assignedDay:'${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}'));}finally{n.dispose();}
 return '${(await d.query('alarms')).singleWhere((r)=>!ids.contains(r['id']))['id']}';})()""".replace('\n',' ').replace("type:'custom'","type:'"+kind+"'"))
 (OUT/'next_extra_id.json').write_text(ident,encoding='utf-8')
else:
 ident=int((OUT/'next_extra_id.json').read_text())
 raw=evaluate('export_next_extra_'+stage,'screens/settings_tab.dart',"(() async {final d=await DatabaseService.instance.database;return jsonEncode({'alarms':await d.query('alarms',orderBy:'id'),'history':await d.query('alarm_history',orderBy:'id'),'overrides':await d.query('alarm_overrides'),'presets':(await SharedPreferences.getInstance()).getString('custom_alarm_presets')});})()")
 (OUT/('next_extra_'+stage+'.json')).write_text(raw,encoding='utf-8')
 assert compare_os('next_extra_'+stage+'_os')
