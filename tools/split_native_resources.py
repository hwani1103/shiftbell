import xml.etree.ElementTree as ET
import json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
keys={'sleep_widget_description','sleep_widget_brand','app_widget_sleep_label',
 'sleep_widget_sleep','sleep_widget_wake','sleep_widget_no_shift','sleep_widget_not_set',
 'sleep_widget_unknown','sleep_widget_tab_off','channel_schedule_notify','one_tap_alarm_label'}
base=ROOT/'android/app/src/main/res'
ko=ET.parse(base/'values-ko/strings.xml')
nodes={n.attrib.get('name'):n for n in ko.getroot()}
scoped=ET.Element('resources')
for key in sorted(keys):
 n=nodes[key];scoped.append(n)
ET.indent(scoped,space='    ')
ET.ElementTree(scoped).write(base/'values/korean_only.xml',encoding='utf-8',xml_declaration=True)
for folder in ['values','values-ko','values-pt','values-de','values-hi']:
 p=base/folder/'strings.xml';s=p.read_text('utf-8')
 for key in keys:
  s=re.sub(r'    <string name="'+key+r'">.*?</string>\r?\n','',s)
 s=s.replace('Keep this key set in sync with values-ko/strings.xml.',
   'Common keys match values-ko/strings.xml. Korean-only features use korean_only.xml.')
 p.write_text(s,'utf-8')
for p in (ROOT/'android/app/src/main/kotlin').rglob('*.kt'):
 if p.name=='KoreanFeatureStrings.kt':continue
 s=p.read_text('utf-8')
 s=re.sub(r'(context|ui)\.getString\(R.string.one_tap_alarm_label\)',r'KoreanFeatureStrings.oneTapLabel(\1)',s)
 s=s.replace('?: ui.getString(if (cursor.getString(2) == "custom" || !cursor.isNull(3))\n                            R.string.one_tap_alarm_label else R.string.alarm_default_label)',
  '?: if (cursor.getString(2) == "custom" || !cursor.isNull(3))\n                            KoreanFeatureStrings.oneTapLabel(ui) else ui.getString(R.string.alarm_default_label)')
 p.write_text(s,'utf-8')
(ROOT/'docs/next_version/후속재점검_2026-10-05/Android_전용범위.json').write_text(json.dumps(sorted(keys),indent=2),'utf-8')
