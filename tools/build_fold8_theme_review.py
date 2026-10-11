"""One large, uncropped native screenshot per scroll section."""
import html
import json
import os
import sys
from pathlib import Path

root = Path(os.environ.get('FOLD_REVIEW_ROOT', str(Path(__file__).resolve().parents[1] / 'artifacts/fold8_theme_review_2026_10_08')))
plan = json.loads((root / 'capture_plan.json').read_text(encoding='utf-8'))
manifest_path = root / 'captures/manifest.json'
manifest = json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.exists() else {'captures': []}
by_key = {(r['locale'], r['theme'], r['posture']): r for r in manifest['captures']}
labels = {
    'ko-KR': {'mainWhite': '메인 화이트', 'mainDark': '메인 다크', 'minimal': '심플 라인',
        'materialCard': '소프트 카드', 'boldGrid': '다크 그리드', 'initialBadge': '이니셜 배지',
        'eventChip': '이벤트 캘린더', 'underline': '언더라인', 'editorial': '매거진', 'diary': '다이어리'},
    'en-US': {'periwinkle': 'Periwinkle', 'softMosaic': 'Soft Mosaic', 'mainWhite': 'Classic White',
        'mainDark': 'Classic Dark', 'minimal': 'Simple Line', 'materialCard': 'Soft Card', 'boldGrid': 'Dark Grid'},
}
locale_filter = sys.argv[1] if len(sys.argv) > 1 else None
selected = [r for r in plan['captures'] if not locale_filter or r['locale'] == locale_filter]
sections = []
for i, expected in enumerate(selected, 1):
    key = expected['locale'], expected['theme'], expected['posture']
    row = by_key.get(key)
    title = f"{'한글' if key[0] == 'ko-KR' else '영어'} · {labels[key[0]][key[1]]} · {'접힘' if key[2] == 'closed' else '펼침'}"
    if row:
        image = f'<img src="captures/{html.escape(row["file"], quote=True)}" alt="{html.escape(title, quote=True)}" loading="lazy">'
        meta = html.escape(row['window'])
    else:
        image = '<p class="pending">캡처 대기</p>'
        meta = '아직 캡처되지 않은 화면'
    sections.append(f'<section id="shot-{i}"><header><span>{i:02d} / {len(selected)}</span><h2>{title}</h2><small>{meta}</small></header><div class="picture">{image}</div></section>')
page = '''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Fold8 달력 테마 실기기 비교</title><style>
*{box-sizing:border-box}html{scroll-snap-type:y proximity;background:#111827;color:#f1f5f9;font-family:system-ui,sans-serif}
body{margin:0}section{height:100vh;height:100dvh;padding:12px 20px 16px;display:flex;flex-direction:column;scroll-snap-align:start}
header{min-height:62px;display:flex;align-items:center;gap:18px;flex-wrap:wrap;justify-content:center}
h2{font-size:21px;margin:0}header span,small{color:#aebbd0}small{font-size:12px}
.picture{min-height:0;flex:1;display:flex;align-items:center;justify-content:center}
img{display:block;width:100%;height:100%;object-fit:contain;image-rendering:auto}.pending{color:#aebbd0}
.controls{position:fixed;right:12px;bottom:12px;display:flex;gap:6px;z-index:2}
button{background:#25334acc;color:white;border:1px solid #6e7c91;border-radius:6px;padding:7px 10px;cursor:pointer}
body.actual section{height:auto;min-height:100vh}body.actual .picture{display:block;text-align:center}body.actual img{width:auto;height:auto;max-width:100%;margin:auto}
</style><div class="controls"><button onclick="document.documentElement.requestFullscreen?.()">전체화면</button><button onclick="document.body.classList.toggle('actual')">화면 맞춤 / 원본 크기</button></div>CONTENT
<script>document.addEventListener('keydown',e=>{if(['ArrowDown','PageDown','ArrowUp','PageUp'].includes(e.key)){e.preventDefault();const step=e.key.endsWith('Down')?1:-1;const n=Math.round(scrollY/innerHeight)+step;document.querySelectorAll('section')[Math.max(0,Math.min(33,n))].scrollIntoView({behavior:'smooth'});}});</script></html>'''.replace('CONTENT', '\n'.join(sections)).replace('Math.min(33,n)', f'Math.min({len(selected)-1},n)')
filename = '한글_화면비교.html' if locale_filter == 'ko-KR' else '영어_화면비교.html' if locale_filter == 'en-US' else '화면비교.html'
(root / filename).write_text(page, encoding='utf-8')
print(f"Gallery: {len(by_key)}/34 actual captures")
