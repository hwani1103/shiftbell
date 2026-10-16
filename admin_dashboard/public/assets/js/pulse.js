import { esc, fmtInt, fmtPct, fmtMD } from './format.js';
import { EVENT_META, localizeName } from './labels.js';
import { comparisonRows, dayShift, constrained } from './pulse-model.js';

const count = n => n == null ? '—' : fmtInt(n);
const rate = n => n == null ? '—' : fmtPct(n, 1);
const panel = (title, sub, body) => `<section class="card span-12 pulse-card"><div class="card-h"><div><h2>${title}</h2><p>${sub}</p></div></div>${body}</section>`;
const note = text => `<p class="sub">${text}</p>`;
const range = r => r ? `${esc(fmtMD(r.from))}–${esc(fmtMD(r.to))}` : '—';
export function pulseHero(docs, ui) {
  const p = docs.pulse, yesterday = p?.today ? dayShift(p.today, -1) : docs.summary.latest;
  const daily = p?.daily?.find(r => r.date === yesterday);
  const today = p?.daily?.find(r => r.date === p.today);
  const ret = docs.growth?.retention?.all?.[7];
  const funnel = docs.growth?.byRange?.[ui.range]?.activation?.all;
  const tiles = [
    ['DAU · 최근 완료일', count(daily?.dau ?? (docs.summary.latest === yesterday ? docs.summary.kpi?.dau : null)), `${esc(fmtMD(yesterday))} · ${p?.today ? esc(fmtMD(p.today)) : '오늘'} ${count(today?.dau)}명 · 잠정`],
    ['D7 재방문율', rate(ret?.rate), `${count(ret?.returned)} / ${count(ret?.size)}명 · ${range(ret)} 첫 세션`],
    ['온보딩 완료율', rate(funnel?.rate), `${count(funnel?.completed)} / ${count(funnel?.entrants)}명 · ${range(funnel)} 첫 실행`],
  ];
  const trend = p?.retention;
  const bars = trend?.map(r => `<div class="pulse-trend-col" title="${esc(r.date)} 기준 · ${range(r)} 첫 세션 · ${count(r.returned)}/${count(r.size)}명"><b>${rate(r.rate)}</b><div class="pulse-trend-track"><i style="height:${r.rate == null ? 0 : Math.max(2, r.rate * 100)}%"></i></div><small>${esc(fmtMD(r.date))}</small></div>`).join('');
  return panel('매일 확인하는 핵심 지표', '이용자 · 재방문 · 신규 사용자 설정 완료',
    `<div class="growth-metrics">${tiles.map(([l,v,n]) => `<article><span>${l}</span><b>${v}</b><small>${n}</small></article>`).join('')}</div>` +
    note('온보딩 완료율은 첫 실행 후 24시간 안에 완료한 같은 사람의 비율입니다. D7은 첫 세션에서 정확히 7일 뒤 다시 온 비율이며, 매일 최근 7일 유입 집단으로 계산합니다. 표본이 적으면 비율이 크게 움직일 수 있습니다.') +
    (bars ? `<details class="growth-help" data-disclosure-id="d7-trend"><summary>D7 추이 · 최근 8회 기준일</summary><div class="pulse-trend">${bars}</div>${note('기준일마다 집단이 하루씩 이동합니다. 막대에 표시되는 기준일은 재방문 집계일이며 설치일이 아닙니다.')}</details>` : ''));
}

export function featureComparison(docs, ui) {
  const model = comparisonRows(docs, ui.featureMode), all = ui.featureAll;
  if (!model.dates.length) return panel('기능 사용량 · 날짜별 비교', '일정 생성 · 수면 기록 · 전체근무표 · 메모 등', note('새 일별 집계를 준비 중입니다.'));
  const rows = all ? model.rows : model.rows.slice(0,15);
  const max = Math.max(1,...model.rows.flatMap(r=>r.values.map(v=>v??0)));
  const controls = `<div class="pulse-controls"><div class="seg" role="group" aria-label="기능 비교 날짜"><button data-action="feature-mode" data-key="live" aria-pressed="${ui.featureMode !== 'closed'}">어제 / 오늘</button><button data-action="feature-mode" data-key="closed" aria-pressed="${ui.featureMode === 'closed'}">그제 / 어제</button></div><button class="btn ghost sm" data-action="feature-all">${all ? '상위 15개만' : `전체 ${model.rows.length}개 보기`}</button></div>`;
  const legend = `<div class="pulse-legend"><span><i class="pulse-before"></i>${esc(fmtMD(model.dates[0]))}</span><span><i class="pulse-after"></i>${esc(fmtMD(model.dates[1]))}${ui.featureMode === 'closed' ? '' : ' · 잠정'}</span><span>실행 횟수 · 두 날짜 합계순</span></div>`;
  const chart = rows.map((r,i) => `<div class="pulse-feature"><button class="pulse-feature-name" data-action="event" data-event="${esc(r.name)}"><span>${i+1}</span>${esc(r.label)}</button><div class="pulse-bars">${r.values.map((v,j)=>`<div class="pulse-bar-row"><div class="pulse-bar-track"><i class="${j?'pulse-after':'pulse-before'}" style="width:${v == null ? 0 : v/max*100}%"></i></div><b>${v == null ? '미관측' : count(v)}</b></div>`).join('')}</div></div>`).join('');
  return panel('어떤 기능을 얼마나 사용하나요?', '일정 생성 · 수면 기록 · 전체근무표 확인 · 메모 저장 등', controls + legend +
    (model.available ? `<div class="pulse-features">${chart}</div>` : note('기능 집계를 가져오지 못했습니다. 0회로 해석하지 마세요.')) +
    note(`오늘은 하루가 끝나지 않았고 GA4 처리 지연도 있어 전일 대비 감소율을 표시하지 않습니다. 공정한 비교는 ‘그제 / 어제’를 선택하세요. 최근 30일 동안 수집되지 않은 기능은 ‘미관측’입니다.${model.limited ? ' 현재 보고서에 집계 제한이 있습니다.' : ''}`));
}

export function newcomerCard(docs, ui) {
  const p = docs.pulse;
  if (!p) return panel('날짜별 신규 설치 현황', 'GA4 첫 실행 기준', note('새 일별 집계를 준비 중입니다.'));
  const date = ui.newcomerDate && ui.newcomerDate >= p.from && ui.newcomerDate <= p.today ? ui.newcomerDate : dayShift(p.today,-1);
  const days = Array.from({length:30},(_,i)=>dayShift(p.today,-i));
  const controls = `<div class="pulse-controls"><label class="pulse-date">첫 실행일 <select id="newcomer-date" aria-label="신규 설치 조회 날짜">${days.map(d=>`<option value="${d}"${d===date?' selected':''}>${esc(fmtMD(d))}${d===p.today?' · 오늘(잠정)':''}</option>`).join('')}</select></label><span>${date===p.today?'오늘은 집계 중입니다':'최근 30일 조회'}</span></div>`;
  if (p.newcomers == null) return panel('날짜별 신규 설치 현황', 'GA4 첫 실행 기준',controls+note('국가·언어별 신규 집계를 확인 중입니다. 조회 실패는 0명으로 표시하지 않습니다.'));
  const rows = p.newcomers.filter(r=>r.date===date).sort((a,b)=>b.firstOpens-a.firstOpens);
  const total = rows.reduce((n,r)=>n+r.firstOpens,0);
  const korean = rows.filter(r=>['South Korea','대한민국'].includes(r.country)).reduce((n,r)=>n+r.firstOpens,0);
  const unknown = rows.filter(r=>!r.country || /^\(/.test(r.country)).reduce((n,r)=>n+r.firstOpens,0);
  const foreign = total-korean-unknown;
  const metrics = `<div class="pulse-cohort-summary"><b>${esc(fmtMD(date))} · ${count(total)}명 관측</b><span>대한민국 ${count(korean)}명 (${total?rate(korean/total):'—'})</span><span>해외 ${count(foreign)}명 (${total?rate(foreign/total):'—'})</span><span>국가 미상 ${count(unknown)}명</span></div>`;
  const table = `<div class="table-scroll"><table class="ops-table pulse-newcomers"><thead><tr><th>국가 / 기기 언어</th><th>첫 실행</th><th>비중</th><th>온보딩 완료</th><th>이후 사용 기능 · 사용자 수</th></tr></thead><tbody>${rows.map(r=>`<tr><th>${esc(localizeName('country',r.country))}<small>${esc(localizeName('language',r.language))}</small></th><td>${count(r.firstOpens)}명</td><td>${total?rate(r.firstOpens/total):'—'}</td><td>${count(r.completed)}명</td><td><div class="pulse-feature-chips">${Object.entries(r.features).filter(([,n])=>n>0).sort((a,b)=>b[1]-a[1]).map(([name,n])=>`<span>${esc(EVENT_META[name]?.label??name)} <b>${count(n)}명</b></span>`).join('') || '<span>추가 사용 미관측</span>'}</div></td></tr>`).join('')}</tbody></table></div>`;
  return panel('날짜별 신규 설치 현황', '국가 · 언어 · 온보딩 · 이후 사용을 한눈에', controls+metrics+(rows.length?table:note('이 날짜에 관측된 신규 사용자 집단이 없습니다.'))+
    note(`${constrained(p.coverage?.newcomers)?'집계 제한이 있어 일부 값이 누락될 수 있습니다. ':''}Play 설치 수가 아닌 GA4 첫 실행 사용자 기준입니다. 비중은 관측된 국가·언어 그룹 합계 기준이며, 국가/언어가 바뀐 사용자는 그룹 간 중복될 수 있습니다. 언어는 기기 언어입니다.`)+
    `<details class="growth-help" data-disclosure-id="newcomer-method"><summary>온보딩·추가 사용 인원은 어떻게 읽나요?</summary>${note('선택한 날 첫 세션을 시작한 집단이 집계 시점까지 수행한 활동입니다. 한 사람은 여러 기능에 포함될 수 있어 기능별 인원을 더하지 않습니다. 국가·언어는 활동 당시 값이므로 이동/언어 변경 시 첫 실행과 완료 행이 달라질 수 있습니다. 개인별 추적 목록이 아니며, 이 표의 완료 인원은 상단의 24시간 온보딩 완료율과 관측 기간이 다릅니다. GA4 처리 지연에 따라 최근 날짜는 후속 집계에서 보완됩니다.')}</details>`);
}
