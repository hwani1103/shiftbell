"""Build a local gallery from widget-test PNGs; no device or image processing."""
import json
from pathlib import Path

folder = Path('build/fold_layout_previews')
files = sorted(p.name for p in folder.glob('*.png'))
page = '''<!doctype html><html lang="ko"><meta charset="utf-8">
<title>폴드 레이아웃 미리보기</title>
<style>
body{font:16px system-ui;margin:24px;background:#f2f4f8;color:#17213b}
header{position:sticky;top:0;background:#f2f4f8;padding:12px 0;z-index:1}
select{font:inherit;padding:8px;max-width:100%} main{display:flex;gap:20px;align-items:flex-start;overflow:auto}
figure{margin:0;flex:0 0 auto}img{display:block;max-height:76vh;max-width:90vw;object-fit:contain;border:1px solid #ccd2df;background:white}
figcaption{padding:10px 0}p{max-width:1000px;line-height:1.6}
</style><header><h1>폴드 레이아웃 미리보기</h1>
<p>로컬 위젯 렌더링입니다. 기기 실측 dp·삼성 글꼴·상태 표시줄·실제 광고는 포함하지 않습니다.
하단 빈 영역은 탭 바와 광고를 위한 테스트 여백입니다. 최종 확인은 SRTL → 대여 실기기 순서입니다.</p>
<label>화면 <select id="screen"></select></label></header><main id="views"></main>
<script>const files=FILES;
const names=[...new Set(files.map(f=>f.replace(/_\\d+x\\d+\\.png$/,'')))];
const screen=document.querySelector('#screen'),views=document.querySelector('#views');
for(const n of names){const o=document.createElement('option');o.value=n;o.textContent=n;screen.append(o)}
const labels={'400x632':'폴드 커버 기준','662x876':'폴드 내부 기준','360x840':'울트라 커버 기준',
'806x895':'울트라 내부 기준','393x852':'일반 폰 회귀 기준','895x806':'가로 창 추가 확인'};
function render(){views.replaceChildren();for(const f of files){if(f.replace(/_\\d+x\\d+\\.png$/,'')!==screen.value)continue;
const size=f.match(/_(\\d+x\\d+)\\.png$/)[1],fig=document.createElement('figure'),cap=document.createElement('figcaption'),img=document.createElement('img');
cap.textContent=(labels[size]||'')+' · '+size+' dp';img.src=f;img.alt=screen.value+' '+size;fig.append(cap,img);views.append(fig)}}
screen.onchange=render;render();</script></html>'''
(folder / 'index.html').write_text(page.replace('FILES', json.dumps(files)), encoding='utf-8')
print(f'Gallery: {len(files)} images in {folder / "index.html"}')
