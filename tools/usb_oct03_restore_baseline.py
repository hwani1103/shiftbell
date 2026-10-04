"""Restore only this audit's dev DB/prefs from its fresh snapshot, then check OS."""
import json
import base64
import xml.etree.ElementTree as ET
from usb_audit_device import adb, evaluate, OUT, SERIAL, PACKAGE, compare_os

assert PACKAGE == 'com.hwani1103.shiftbell.dev' and SERIAL == 'R5KL20DHWAE'
def original(name):
    return json.loads((OUT / name).read_text(encoding='utf-8'))['valueAsString']

data = {'tables': json.loads(original('export_remaining_all_tables.vm.json')),
        'prefs': json.loads(original('export_remaining_original_prefs.vm.json'))}
values={n.get('name'):n.get('value') for n in ET.fromstring(adb('exec-out','run-as',PACKAGE,'cat','/data/user_de/0/'+PACKAGE+'/shared_prefs/alarm_state.xml'))}
active=int(values.get('currently_ringing_alarm_id','-1'))
original_ids={row['id'] for row in data['tables']['alarms']}
if active>=0 and active not in original_ids:
    adb('shell','run-as',PACKAGE,'/system/bin/am','broadcast','--user','0',
        '-n',PACKAGE+'/com.hwani1103.shiftbell.AlarmActionReceiver','-a','DISMISS_FROM_NOTIFICATION',
        '--ei','alarmId',str(active),'--el','ringRound',values['currently_ringing_round'])
encoded = base64.b64encode(json.dumps(data, ensure_ascii=False).encode()).decode()
expression = f"""(() async {{
 final source=jsonDecode(utf8.decode(base64Decode('{encoded}'))) as Map;
 final d=await DatabaseService.instance.database;
 final oldIds=(await d.query('alarms')).map((r)=>r['id'] as int).toList();
 final tables=source['tables'] as Map;
 await d.transaction((tx) async {{
   for(final entry in tables.entries) {{
     final name=entry.key as String;
     if(name=='android_metadata') continue;
     await tx.delete(name);
     for(final row in entry.value as List) {{await tx.insert(name,Map<String,dynamic>.from(row as Map));}}
   }}
 }});
 for(final id in oldIds){{await kAlarmChannel.invokeMethod('cancelNativeAlarm',{{'id':id}});}}
 final prefs=await SharedPreferences.getInstance();final originals=source['prefs'] as Map;
 for(final key in prefs.getKeys().toList()){{if(!originals.containsKey(key)) await prefs.remove(key);}}
 for(final entry in originals.entries){{
   final k=entry.key as String;final v=entry.value;
   if(v is bool){{await prefs.setBool(k,v);}}else if(v is int){{await prefs.setInt(k,v);}}
   else if(v is double){{await prefs.setDouble(k,v);}}else if(v is String){{await prefs.setString(k,v);}}
   else if(v is List){{await prefs.setStringList(k,v.cast<String>());}}
 }}
 final refreshed=await kAlarmChannel.invokeMethod<bool>('forceNativeRefreshAndWait');
 final differences=<String>[];
 for(final entry in tables.entries){{
   if(entry.key=='android_metadata') continue;
   if(jsonEncode(await d.query(entry.key as String,orderBy:'rowid'))!=jsonEncode(entry.value))differences.add(entry.key as String);
 }}
 if(differences.isNotEmpty) throw StateError('Original table differences: $differences');
 return 'all original user tables restored; native refresh=$refreshed';
}})()"""
evaluate('remaining_restore_original_tables_prefs', 'screens/settings_tab.dart', expression.replace('\n', ' '), timeout=120)
assert compare_os('remaining_restored_os')
print('Original user tables and OS reservations restored.')
