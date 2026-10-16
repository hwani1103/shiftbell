"""Export existing reviewed app holiday names for the offline native widget."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'lib/utils/holiday_util.dart').read_text(encoding='utf-8')
def korean_map(name):
    block = re.search(r'const Map<String, String> ' + name + r' = \{(.*?)\};', source, re.S)
    return dict(re.findall(r"'([0-9-]+)': '([^']+)'", block[1]))

result = {'KR': {'fixed': korean_map('fixedHolidays'), 'days': korean_map('lunarHolidays')}}
expected = json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + '\n'
path = ROOT / 'android/app/src/main/assets/calendar_holiday_names.json'
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
if parser.parse_args().check:
    assert path.read_text(encoding='utf-8') == expected, 'Regenerate widget holiday names'
else:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(expected, encoding='utf-8')
print('Offline widget holiday names match app sources: OK')
