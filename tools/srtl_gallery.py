"""Offline review index: original device PNGs, filterable without a server."""
import json
from pathlib import Path
root=Path('artifacts/srtl_2026-10-03/Fold8Ultra')
rows=[]
for directory in [root/'numbered_v3', root/'scale_1.3']:
    manifest=directory/'manifest.json'
    if not manifest.exists():continue
    for row in json.loads(manifest.read_text(encoding='utf-8')).get('captures',[]):
        if row.get('status') not in ('captured','reviewed_pass'):continue
        rows.append({**row,'path':directory.name+'/'+row['filename']})
html='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Fold8 Ultra 원본 화면 비교</title><style>
body{margin:0;background:#edf0f5;color:#202635;font:15px system-ui,sans-serif}header{padding:20px;background:white;position:sticky;top:0;z-index:1;border-bottom:1px solid #ccd3df}h1{font-size:21px;margin:0 0 8px}p{margin:6px 0;line-height:1.6}select,button{font:inherit;padding:8px;margin:4px;border:1px solid #bac3d3;border-radius:8px;background:white}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:20px;padding:20px}article{background:white;border-radius:12px;padding:12px;max-width:760px}h2{font-size:15px;margin:0 0 8px}img{display:block;width:100%;height:550px;object-fit:contain;background:#f7f8fa}a{color:#334cac}.meta{font-size:12px;color:#596372}dialog{border:0;border-radius:12px;width:94vw;max-width:1500px;height:90vh;padding:12px}dialog::backdrop{background:#000a}dialog img{width:auto;height:auto;max-width:none;background:white}#view{overflow:auto;height:calc(100% - 48px)}.fit img{max-width:100%;height:auto;margin:auto}#count{font-weight:600}
</style><header><h1>Fold8 Ultra · 원본 화면 비교</h1>
<p>기기에서 직접 추출한 PNG입니다. 기본은 글자 배율 1.0입니다. 이미지를 누르면 화면 맞춤 또는 원본 픽셀 크기로 볼 수 있습니다.</p>
<p class="meta">2026-10-04 메모 여백 수정 후 1.0·1.3 전체 재촬영본입니다. 레이아웃 검토 결과이며 사용자의 최종 가독성 판단과 구분합니다. 웹은 현재 소스의 로컬 테스트 데이터이며 실서버 공유·실제 PWA 설치 검증이 아닙니다.</p>
<p class="meta"><a href="../../../docs/next_version/교대시계_최신문서.txt">최신 현황과 남은 검증</a> · 1.3 웹 하단 스크롤: <a href="web_bottom/friend_web_ko_closed_1.3_bottom.png">한글</a> / <a href="web_bottom/friend_web_en_closed_1.3_bottom.png">영어</a></p>
<select id="scale"><option>1.0</option><option>1.3</option></select>
<select id="lang"><option value="">모든 언어</option><option>ko-KR</option><option>en-US</option></select>
<select id="posture"><option value="">접힘 + 펼침</option><option value="closed">접힘</option><option value="open">펼침</option></select>
<select id="screen"><option value="">전체 화면</option><option value="main">메인 달력</option><option value="roster">전체 조 근무표</option><option value="friend">친구 공유 웹</option></select>
<span id="count"></span></header><main id="grid"></main>
<dialog id="dialog"><button id="close">닫기</button><button id="fit">화면 맞춤 / 원본 크기</button><a id="original" target="_blank">원본 PNG 열기</a><div id="view" class="fit"><img id="large"></div></dialog>
<script>const rows=DATA;const $=id=>document.getElementById(id);function render(){const chosen=rows.filter(r=>String(r.font_scale||'1.0')===$('scale').value&&(!$('lang').value||r.language===$('lang').value)&&(!$('posture').value||r.posture===$('posture').value)&&(!$('screen').value||r.screen===$('screen').value)).sort((a,b)=>a.number.localeCompare(b.number));$('grid').replaceChildren();$('count').textContent=chosen.length+'장';for(const r of chosen){const article=document.createElement('article'),h=document.createElement('h2'),im=document.createElement('img'),p=document.createElement('p');h.textContent=r.number+' · '+r.variant+' · '+r.language+' · '+(r.posture==='open'?'펼침':'접힘');im.src=r.path;im.loading='lazy';im.alt=h.textContent;p.className='meta';p.textContent='배율 '+r.font_scale+' · '+(r.pixels||[]).join(' × ');im.onclick=()=>{$('large').src=r.path;$('original').href=r.path;$('view').className='fit';$('dialog').showModal()};article.append(h,im,p);$('grid').append(article)}}for(const id of ['scale','lang','posture','screen'])$(id).onchange=render;$('close').onclick=()=>$('dialog').close();$('fit').onclick=()=>$('view').classList.toggle('fit');render();</script></html>'''
(root/'화면비교.html').write_text(html.replace('DATA',json.dumps(rows,ensure_ascii=False)),encoding='utf-8')
print('Gallery:',len(rows),'images')
