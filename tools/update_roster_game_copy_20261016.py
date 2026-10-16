"""Add full-roster view labels and the mini-game entry in every app language."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
values = {
    'ko': ['두 구역 보기', '한눈에 보기', '미니게임'],
    'en': ['Two-section view', 'Month overview', 'Mini-games'],
    'de': ['Ansicht in zwei Abschnitten', 'Monatsübersicht', 'Minispiele'],
    'pt': ['Visualização em duas partes', 'Visão mensal', 'Minijogos'],
    'hi': ['दो भागों में देखें', 'पूरा महीना देखें', 'मिनी गेम'],
}
keys = ['allShiftsTimelineLayout', 'allShiftsOverviewLayout', 'settingsMiniGamesTitle']
for locale, strings in values.items():
    path = root / f'lib/l10n/app_{locale}.arb'
    text = path.read_text(encoding='utf-8')
    data = json.loads(text)
    missing = {k: v for k, v in zip(keys, strings) if k not in data}
    if missing:
        at = text.rfind('}')
        additions = json.dumps(missing, ensure_ascii=False, indent=2)[1:-1]
        path.write_text(text[:at].rstrip() + ',' + additions + '\n}\n', encoding='utf-8')
