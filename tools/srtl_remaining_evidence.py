"""Offline integrity and coverage inventory; never labels screenshots as visual PASS."""
import json, re
from pathlib import Path
from PIL import Image

root = Path('build/srtl_2026-10-03_ultra_remaining')
valid, invalid = [], []
for path in sorted(root.glob('*.png')):
    try:
        with Image.open(path) as im:
            size = list(im.size)
            im.verify()
        valid.append({'file': path.name, 'pixels': size})
    except Exception as error:
        invalid.append({'file': path.name, 'error': str(error)})
route_coverage = {}
for item in valid:
    match = re.fullmatch(r'(ko-KR|en-US)_(closed|open)_1\.3_(.+)_sweep_(1\.[0-3])\.png', item['file'])
    if match:
        lang, posture, screen, scale = match.groups()
        route_coverage.setdefault(lang+'/'+posture+'/'+screen, []).append(scale)
report = {'valid': valid, 'invalid': invalid, 'remaining_route_capture_coverage': route_coverage,
          'note': 'Integrity only. navigation_check.png is a bootstrap lock screen, not app evidence.'}
(root / 'png_integrity.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
print(json.dumps({'valid': len(valid), 'invalid': invalid}))
