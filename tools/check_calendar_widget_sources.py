"""Build-free source/resource checks. Does not replace native or launcher tests."""
import json
import re
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / 'android/app/src/main/res'
SRC = ROOT / 'android/app/src/main/kotlin/com/hwani1103/shiftbell'
A = '{http://schemas.android.com/apk/res/android}'

def ids(name):
    return {n.attrib[A+'id'].split('/')[-1] for n in ET.parse(RES/'layout'/name).iter() if A+'id' in n.attrib}

class CalendarWidgetSources(unittest.TestCase):
    def test_six_rows_have_dates_shifts_holidays_and_three_memos(self):
        actual = ids('calendar_widget_grid.xml')
        for row in range(6):
            self.assertIn(f'widget_row_{row}', actual)
            for col in range(7):
                for role in ['cell','num','numwrap','pill','pillbg','holiday','memo1','memo2','memo3']:
                    self.assertIn(f'{role}_{row}_{col}', actual)
        rows = [n for n in ET.parse(RES/'layout/calendar_widget_grid.xml').iter()
                if n.attrib.get(A+'id','').startswith('@+id/widget_row_')]
        self.assertEqual([n.attrib[A+'visibility'] for n in rows], ['visible']*3+['gone']*3)

    def test_week_is_still_exactly_seven_days_without_holiday_or_navigation(self):
        actual = ids('calendar_widget_week.xml')
        self.assertEqual(len([name for name in actual if name.startswith('num_')]), 7)
        self.assertFalse(any(name.startswith('holiday_') or name.startswith('widget_month') for name in actual))
        backup = ROOT/'artifacts/widget_month_2026_10_16/before/calendar_widget_week.xml'
        if backup.exists():
            self.assertEqual(backup.read_text('utf-8'), (RES/'layout/calendar_widget_week.xml').read_text('utf-8'))

    def test_provider_ids_resolve_and_navigation_receiver_is_private(self):
        actual = ids('calendar_widget.xml') | ids('calendar_widget_grid.xml') | ids('calendar_widget_week.xml')
        referenced = set(re.findall(r'R\.id\.(\w+)', (SRC/'CalendarWidgetProvider.kt').read_text('utf-8')))
        self.assertFalse(referenced - actual, referenced - actual)
        manifest = ET.parse(ROOT/'android/app/src/main/AndroidManifest.xml')
        receiver = next(n for n in manifest.iter('receiver') if n.attrib.get(A+'name') == '.CalendarWidgetNavigationReceiver')
        self.assertEqual(receiver.attrib[A+'exported'], 'false')

    def test_resize_is_vertical_only_for_multi_widget(self):
        multi = ET.parse(RES/'xml/calendar_widget_info.xml').getroot()
        week = ET.parse(RES/'xml/calendar_widget_week_info.xml').getroot()
        self.assertIn('vertical', multi.attrib[A+'resizeMode'])
        self.assertNotIn('vertical', week.attrib[A+'resizeMode'])

    def test_holiday_names_are_korean_only_and_match_native_red_days(self):
        data = json.loads((ROOT/'android/app/src/main/assets/calendar_holiday_names.json').read_text('utf-8'))
        self.assertEqual(set(data), {'KR'})
        source = (SRC/'CalendarWidgetHolidays.kt').read_text('utf-8')
        self.assertIn('if (!ReleaseLocalePolicy.koreanFeatures(context)) return null', source)
        for group, field in [('FIXED_HOLIDAYS','fixed'), ('LUNAR_HOLIDAYS','days')]:
            block = re.search(group+r' = setOf\((.*?)\n    \)', source, re.S)[1]
            self.assertEqual(set(re.findall(r'"([0-9-]+)"',block)), set(data['KR'][field]))

    def test_new_strings_resolve_for_all_release_languages(self):
        for folder in ['values', 'values-ko', 'values-de', 'values-pt', 'values-hi']:
            strings = {node.attrib['name']: node.text for node in ET.parse(RES/folder/'strings.xml').iter('string')}
            for key in ['widget_previous_month', 'widget_next_month', 'calendar_widget_description']:
                self.assertTrue(strings[key].strip())
            self.assertNotIn('widget_public_holiday', strings)
        scoped = {node.attrib['name']: node.text for node in ET.parse(RES/'values/korean_only.xml').iter('string')}
        self.assertEqual(scoped['widget_public_holiday'], '공휴일')

    def test_widget_navigation_and_cache_have_no_remote_data_requests(self):
        for name in ['CalendarWidgetMonths.kt', 'CalendarWidgetNavigationReceiver.kt']:
            source = (SRC/name).read_text('utf-8')
            self.assertNotRegex(source, r'import (com\.google\.firebase|okhttp|java\.net)')
        self.assertIn('putExtra("openTab", 2)', (SRC/'CalendarWidgetProvider.kt').read_text('utf-8'))

if __name__ == '__main__':
    unittest.main(verbosity=2)
