"""Stable cross-device screenshot IDs. Never infer completion from file existence."""
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/srtl_2026-10-03'
THEMES = ['mainWhite', 'mainDark', 'minimal', 'materialCard', 'boldGrid',
          'initialBadge', 'underline', 'eventChip', 'editorial', 'diary']
DEVICES = ['Fold8Ultra', 'Fold8', 'Flip8', 'Flip4']
rows = []

def add(screen, variant, language, posture, fixture):
    number = f'{len(rows)+1:03d}'
    rows.append(dict(number=number, screen=screen, variant=variant,
                     language=language, posture=posture, fixture=fixture,
                     font_scale='1.0', month='2026-10',
                     filename=f'{number}_{screen}_{variant}_{language}_{posture}.png'))

for theme in THEMES:
    for language in ['ko-KR', 'en-US']:
        for posture in ['closed', 'open']:
            add('main', theme, language, posture, 'varied-long-shifts-multiple-memos-v2')
for variant in ['common', 'individual']:
    for language in ['ko-KR', 'en-US']:
        for posture in ['closed', 'open']:
            add('roster', variant, language, posture, 'long-shifts-valid-single-character-teams-v2')
for variant in ['pwa0', 'pwa1']:
    for language in ['ko-KR', 'en-US']:
        for posture in ['closed', 'open']:
            add('friend', variant, language, posture, 'varied-long-shifts-exceptions-no-memo-v2')

OUT.mkdir(parents=True, exist_ok=True)
(OUT/'capture_catalog.json').write_text(json.dumps({
    'version': 2, 'devices': DEVICES,
    'rules': [
        'Numbers are fixed across devices; unsupported cases retain their number.',
        'English themes unavailable in the app are N/A, never force-enabled.',
        'Flip closed means the actual cover display; unsupported app execution is N/A.',
        'Friend sharing excludes memos by design. No memo-sharing feature is implied.',
        'Existing v1 captures are historical; v2 requires its declared fixture.',
        'Each completed capture must record actual device, pixels, APK/web build hash and fixture.',
        'Large-font diagnostic checks are separate from these comparison originals.'
    ], 'captures': rows}, ensure_ascii=False, indent=2), encoding='utf-8')
with (OUT/'capture_catalog.csv').open('w', encoding='utf-8-sig', newline='') as f:
    writer=csv.DictWriter(f, fieldnames=list(rows[0]))
    writer.writeheader(); writer.writerows(rows)
print(f'{len(rows)} stable capture IDs written; no captures marked complete.')
