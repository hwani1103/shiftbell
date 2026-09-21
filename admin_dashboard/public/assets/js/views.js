// admin_dashboard/public/assets/js/views.js
// 화면 조각을 만드는 곳. HTML 문자열을 돌려주는 함수와, 붙인 뒤 차트를 그리는 mountCharts()로 나뉜다.

import { lineChart, barChart, sparkline, donut, hbarList } from './charts.js';
import { fmtInt, fmtCompact, fmtPct, fmtDur, fmtMoney, fmtMD, fmtLong, relTime, deltaInfo, sum, avg, bucketize, esc } from './format.js';
import { eventMeta, isSystemEvent, BREAKDOWNS, localizeName, osLabel, COLORS } from './labels.js';

export const RANGES = [7, 30, 100, 365];

export const ICONS = {
  bell: '<svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><path d="M6 8a6 6 0 0 1 12 0c0 7 3 8 3 8H3s3-1 3-8"/><path d="M10.3 20a1.9 1.9 0 0 0 3.4 0"/></svg>',
  refresh: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-2.6-6.4"/><path d="M21 4v5h-5"/></svg>',
  eye: '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg>',
};
export const brandMark = `<div class="mark">${ICONS.bell}</div>`;

// ───────────────────────── 파생 데이터 ─────────────────────────

/** 선택한 기간(range)에 맞춰 시리즈를 자르고, 직전 같은 길이 기간도 함께 준비한다. */
export function computeView(docs, range) {
  const { series } = docs;
  const n = series.dates.length;
  const len = Math.min(range, n);
  const from = n - len;
  const pf = from - len;
  return {
    n, len, from,
    hasPrev: pf >= 0,
    dates: series.dates.slice(from),
    cur: (k) => series[k].slice(from),
    prev: (k) => (pf >= 0 ? series[k].slice(pf, from) : []),
    last: (k) => series[k][n - 1] ?? 0,
  };
}

function eventRange(docs, view, name) {
  const arr = docs.events.series?.[name];
  return arr ? arr.slice(view.from) : [];
}

// ───────────────────────── 조각 HTML ─────────────────────────

function deltaChip(d, { suffix = '', inverse = false } = {}) {
  if (d.dir == null) return '<span class="delta">비교 데이터 없음</span>';
  if (d.dir === 'new') return `<span class="delta up${inverse ? ' inv' : ''}">신규</span>`;
  if (d.dir === 'flat') return '<span class="delta">변화 없음</span>';
  const arrow = d.dir === 'up' ? '▲' : '▼';
  return `<span class="delta ${d.dir}${inverse ? ' inv' : ''}">${arrow} ${Math.abs(d.pct * 100).toFixed(1).replace(/\.0$/, '')}%${suffix}</span>`;
}

function kpi({ label, color, value, unit = '', note, delta, spark }) {
  return `<div class="kpi"><div class="lab"><i style="background:${color}"></i>${esc(label)}</div>
    <div class="val">${value}<small>${esc(unit)}</small></div>
    <div class="kfoot"><div>${delta ?? ''}<div class="note">${note ?? ''}</div></div>${spark ?? ''}</div></div>`;
}

export function kpiGrid(docs, view) {
  const s = docs.series;
  const n = view.n;
  const dauCur = view.cur('dau'); const dauPrev = view.prev('dau');
  const dauDelta = view.hasPrev ? deltaInfo(avg(dauCur), avg(dauPrev)) : { pct: null, dir: null };
  const mauNow = view.last('mau');
  const mauThen = n - 1 - view.len >= 0 ? s.mau[n - 1 - view.len] : null;
  const mauDelta = mauThen != null ? deltaInfo(mauNow, mauThen) : { pct: null, dir: null };
  const inst = view.cur('installs'); const instPrev = view.prev('installs');
  const instDelta = view.hasPrev ? deltaInfo(sum(inst), sum(instPrev)) : { pct: null, dir: null };
  const stick = mauNow > 0 ? view.last('dau') / mauNow : 0;
  const stickAvg = avg(view.cur('dau').map((d, i) => (view.cur('mau')[i] > 0 ? d / view.cur('mau')[i] : 0)));
  const label = `${view.len}일`;
  return `<section class="kpis" aria-label="핵심 지표">
    ${kpi({ label: '일간 활성(DAU)', color: COLORS.dau, value: fmtInt(view.last('dau')), unit: '명',
      note: `${label} 평균 ${fmtInt(avg(dauCur))}명`, delta: deltaChip(dauDelta), spark: sparkline(dauCur, COLORS.dau) })}
    ${kpi({ label: '월간 활성(MAU)', color: COLORS.mau, value: fmtInt(mauNow), unit: '명',
      note: '최근 28일 기준', delta: deltaChip(mauDelta), spark: sparkline(view.cur('mau'), COLORS.mau) })}
    ${kpi({ label: `신규 설치 (${label})`, color: COLORS.install, value: fmtInt(sum(inst)), unit: '건',
      note: `하루 평균 ${(sum(inst) / Math.max(1, view.len)).toFixed(1)}건`, delta: deltaChip(instDelta), spark: sparkline(inst, COLORS.install) })}
    ${kpi({ label: '사용 정착도', color: COLORS.wau, value: fmtPct(stick, 0).replace('%', ''), unit: '%',
      note: `DAU÷MAU · 평균 ${fmtPct(stickAvg, 0)}`, delta: '', spark: sparkline(view.cur('dau').map((d, i) => (view.cur('mau')[i] > 0 ? d / view.cur('mau')[i] : 0)), COLORS.wau) })}
  </section>`;
}

/** 자동 요약 문장(2~3줄). */
export function insights(docs, view) {
  const s = docs.series; const n = view.n; const out = [];
  if (!n) return out;
  const latest = s.dates[n - 1];
  const base = n >= 8 ? avg(s.dau.slice(n - 8, n - 1)) : null;
  const d = base != null ? deltaInfo(s.dau[n - 1], base) : null;
  let line = `<b>${fmtLong(latest)}</b> 활성 사용자는 <b>${fmtInt(s.dau[n - 1])}명</b>`;
  if (d?.pct != null) line += `, 직전 7일 평균(${fmtInt(base)}명)보다 <b>${d.pct >= 0 ? '+' : ''}${(d.pct * 100).toFixed(0)}%</b>`;
  out.push(`${line}이에요.`);
  const inst = sum(view.cur('installs')); const rem = sum(view.cur('uninstalls'));
  out.push(`최근 ${view.len}일 신규 설치 <b>${fmtInt(inst)}건</b>, 삭제 <b>${fmtInt(rem)}건</b>(순증 <b>${inst - rem >= 0 ? '+' : ''}${fmtInt(inst - rem)}</b>).`);
  const c = docs.summary.cohort;
  if (c && c.days.length > 7) out.push(`설치 다음 날 다시 쓰는 비율 <b>${fmtPct(c.days[1], 0)}</b>, 7일 뒤에도 쓰는 비율 <b>${fmtPct(c.days[7], 0)}</b>이에요.`);
  else {
    const top = topEvent(docs, view);
    if (top) out.push(`가장 많이 쓰인 기능은 <b>${esc(eventMeta(top.name).label)}</b>(${fmtInt(top.total)}회)예요.`);
  }
  return out;
}

function topEvent(docs, view) {
  let best = null;
  for (const name of Object.keys(docs.events.series ?? {})) {
    if (isSystemEvent(name)) continue;
    const total = sum(eventRange(docs, view, name));
    if (total > 0 && (!best || total > best.total)) best = { name, total };
  }
  return best;
}

export function insightCard(docs, view) {
  const lines = insights(docs, view);
  return `<section class="card insight span-12"><h2>한눈에 보기</h2><ul>${lines.map((l) => `<li>${l}</li>`).join('')}</ul></section>`;
}

function legendChips(items, visible) {
  return `<div class="legend" role="group" aria-label="표시할 지표">${items.map((it) =>
    `<button class="chip" style="--c:${it.color}" data-action="legend" data-key="${it.key}" aria-pressed="${visible[it.key] !== false}"><i style="background:${it.color}"></i>${esc(it.label)}</button>`).join('')}</div>`;
}

export function usersCard(view, visible) {
  return `<section class="card span-8"><div class="card-h"><div><h2>활성 사용자 추이</h2><p>하루·7일·28일 동안 한 번이라도 앱을 쓴 사용자 수</p></div></div>
    ${legendChips([{ key: 'dau', label: 'DAU 일간', color: COLORS.dau }, { key: 'wau', label: 'WAU 주간', color: COLORS.wau }, { key: 'mau', label: 'MAU 월간', color: COLORS.mau }], visible)}
    <div id="ch-users" style="min-height:230px"></div></section>`;
}

/** 막대 묶음 크기: 짧은 기간은 하루 단위, 긴 기간은 주 단위. */
const bucketSize = (len) => (len <= 30 ? 1 : 7);

export function installsCard(view) {
  const inst = sum(view.cur('installs')); const rem = sum(view.cur('uninstalls')); const net = inst - rem;
  const b = bucketSize(view.len);
  return `<section class="card span-4"><div class="card-h"><div><h2>설치 · 삭제</h2><p>${b === 1 ? '하루 단위' : '주 단위 합계'} · 설치는 앱 첫 실행 기준</p></div></div>
    <div id="ch-installs" style="min-height:200px"></div>
    <div class="stats"><div class="stat"><b>${fmtInt(inst)}</b><span>설치</span></div><div class="stat"><b>${fmtInt(rem)}</b><span>삭제</span></div><div class="stat ${net >= 0 ? 'pos' : 'neg'}"><b>${net >= 0 ? '+' : ''}${fmtInt(net)}</b><span>순증</span></div></div>
    <p class="sub" style="margin:10px 0 0">삭제는 구글이 감지한 경우만 집계돼 실제보다 적을 수 있어요.</p></section>`;
}

export function engagementCard(view) {
  const sessions = view.cur('sessions'); const dau = view.cur('dau'); const eng = view.cur('engagementSec');
  const totalSessions = sum(sessions); const totalDau = sum(dau);
  const perUser = totalDau > 0 ? totalSessions / totalDau : 0;
  const dur = totalDau > 0 ? sum(eng) / totalDau : 0;
  return `<section class="card span-6"><div class="card-h"><div><h2>사용 정도</h2><p>얼마나 자주, 얼마나 오래 쓰는지 (${view.len}일 평균)</p></div></div>
    <div class="stats"><div class="stat"><b>${perUser.toFixed(1)}회</b><span>사용자당 하루 세션</span></div><div class="stat"><b>${fmtDur(dur)}</b><span>사용자당 하루 사용시간</span></div><div class="stat"><b>${fmtCompact(totalSessions)}</b><span>총 세션</span></div></div>
    <div id="ch-sessions" style="margin-top:12px;min-height:170px"></div></section>`;
}

export function retentionCard(docs) {
  const c = docs.summary.cohort;
  let body;
  if (!c) {
    body = `<div class="empty"><div class="em">🌱</div><b>아직 계산할 만큼 사용자가 쌓이지 않았어요</b><p>설치한 지 2주가 지난 사용자가 생기면 “설치 후 며칠 뒤에도 쓰는지”가 여기에 나타나요.</p></div>`;
  } else {
    const pick = [[1, '1일 뒤'], [3, '3일 뒤'], [7, '7일 뒤'], [14, '14일 뒤']].filter(([d]) => c.days[d] != null);
    body = `<div class="ret">${pick.map(([d, name]) => `<div><div class="col"><i style="height:${Math.max(3, c.days[d] * 100)}%"></i></div><b>${fmtPct(c.days[d], 0)}</b><span>${name}</span></div>`).join('')}</div>
      <p class="sub" style="margin:12px 0 0">${esc(fmtMD(c.from))} ~ ${esc(fmtMD(c.to))}에 처음 쓴 ${fmtInt(c.size)}명 기준</p>`;
  }
  return `<section class="card span-6"><div class="card-h"><div><h2>다시 쓰는 비율(리텐션)</h2><p>설치한 사용자가 며칠 뒤에도 앱을 여는 비율</p></div></div>${body}</section>`;
}

export function adsCard(docs, view) {
  if (!docs.summary.flags?.ads) {
    return `<section class="card span-12"><div class="card-h"><div><h2>광고</h2><p>배너 광고 노출·클릭·수익</p></div></div>
      <div class="notice"><span class="ic">📢</span><div><b>아직 광고 데이터가 없어요.</b><br>AdMob과 Firebase를 연결하면 노출·클릭·수익이 자동으로 들어와요. (AdMob → 앱 설정 → Firebase 연결) 연결 뒤 하루 정도 지나면 이 카드가 채워져요.</div></div></section>`;
  }
  const imp = sum(view.cur('adImpressions')); const clk = sum(view.cur('adClicks')); const rev = sum(view.cur('adRevenue'));
  const cur = docs.summary.currency ?? 'USD';
  return `<section class="card span-12"><div class="card-h"><div><h2>광고</h2><p>배너 광고 노출·클릭·수익 (${view.len}일)</p></div></div>
    <div class="stats" style="grid-template-columns:repeat(4,minmax(0,1fr))"><div class="stat"><b>${fmtCompact(imp)}</b><span>노출</span></div><div class="stat"><b>${fmtInt(clk)}</b><span>클릭</span></div><div class="stat"><b>${imp > 0 ? fmtPct(clk / imp, 2) : '-'}</b><span>클릭률</span></div><div class="stat"><b>${fmtMoney(rev, cur)}</b><span>수익</span></div></div>
    <div id="ch-ads" style="margin-top:12px;min-height:190px"></div></section>`;
}

// ───────────────────────── 사용자 행동 ─────────────────────────

const GROUP_ORDER = ['시작', '알람', '달력', '일정', '수면', '공유', '백업', '사용', '기타'];

function eventRows(docs, view, { group, includeSystem }) {
  const users30 = new Map((docs.summary.events ?? []).map((e) => [e.name, e.users]));
  const rows = [];
  for (const name of Object.keys(docs.events.series ?? {})) {
    const meta = eventMeta(name);
    const system = meta.group === 'system';
    if (system && !includeSystem) continue;
    if (group !== 'all' && meta.group !== group) continue;
    // 탭 이동은 다른 기능보다 수십 배 많아 순위 막대를 점으로 만든다 - 전체 순위에서는 빼고 '사용' 분류에서만 보여 준다.
    if (group === 'all' && name === 'tab_selected') continue;
    const arr = eventRange(docs, view, name);
    const total = sum(arr);
    if (total <= 0) continue;
    rows.push({ name, meta, total, perDay: total / Math.max(1, view.len), users: users30.get(name) });
  }
  return rows.sort((a, b) => b.total - a.total);
}

export function behaviorCard(docs, view, ui) {
  const hasCustom = !!docs.summary.flags?.customEvents;
  const groups = new Set();
  Object.keys(docs.events.series ?? {}).forEach((n) => { const g = eventMeta(n).group; if (g !== 'system') groups.add(g); });
  const tabs = ['all', ...GROUP_ORDER.filter((g) => groups.has(g))];
  const includeSystem = ui.evSystem || !hasCustom;
  const rows = eventRows(docs, view, { group: ui.evGroup, includeSystem });
  const max = rows.length ? rows[0].total : 1;
  const tabHtml = hasCustom ? `<div class="tabs" role="group" aria-label="분류">${tabs.map((g) =>
    `<button class="tab" data-action="evgroup" data-key="${g}" aria-pressed="${ui.evGroup === g}">${g === 'all' ? '전체' : g}</button>`).join('')}</div>` : '';
  const list = rows.length
    ? hbarList(rows.map((r, i) => ({
      label: r.meta.label, icon: r.meta.icon, value: r.total, display: `${fmtInt(r.total)}회`,
      sub: `하루 평균 ${r.perDay < 10 ? r.perDay.toFixed(1) : fmtInt(r.perDay)}회${r.users != null ? ` · 최근 30일 ${fmtInt(r.users)}명이 사용` : ''}`,
      color: COLORS.palette[i % COLORS.palette.length], attrs: `data-action="event" data-event="${esc(r.name)}" tabindex="0" role="button" aria-label="${esc(r.meta.label)} 자세히"`,
    })), { max })
    : `<div class="empty"><div class="em">🧭</div><b>이 기간에 기록된 이벤트가 없어요</b><p>다른 기간이나 분류를 골라 보세요.</p></div>`;
  const notice = hasCustom ? '' : `<div class="notice" style="margin-bottom:14px"><span class="ic">🚀</span><div><b>사용자 행동 이벤트는 다음 업데이트부터 쌓여요.</b><br>알람·달력·일정·수면 같은 기능 사용량은 계측이 들어간 버전을 배포한 뒤부터 보여요. 지금은 기본 이벤트만 표시돼요.</div></div>`;
  const toggle = hasCustom ? `<button class="chip" style="--c:#94A3B8" data-action="evsystem" aria-pressed="${ui.evSystem}"><i style="background:#94A3B8"></i>기본 이벤트 포함</button>` : '';
  return `<section class="card span-7"><div class="card-h"><div><h2>사용자 행동</h2><p>${view.len}일 동안 기능별 사용 횟수 · 눌러서 추이 보기</p></div>${toggle}</div>${notice}${tabHtml}${list}</section>`;
}

// ───────────────────────── 분포 ─────────────────────────

export function distCard(docs, ui) {
  const tabs = `<div class="tabs" role="group" aria-label="분포 기준">${BREAKDOWNS.map((b) =>
    `<button class="tab" data-action="dist" data-key="${b.key}" aria-pressed="${ui.dist === b.key}">${b.label}</button>`).join('')}</div>`;
  const raw = docs.summary.breakdowns?.[ui.dist] ?? [];
  const items = raw.map((r) => ({ label: ui.dist === 'os' ? osLabel(r.name) : localizeName(ui.dist, r.name), value: r.users }));
  const total = sum(items.map((i) => i.value));
  let body;
  if (!items.length) body = `<div class="empty"><div class="em">📊</div><b>아직 데이터가 없어요</b><p>사용자가 쌓이면 분포가 표시돼요.</p></div>`;
  else {
    const top = items.slice(0, 5); const rest = sum(items.slice(5).map((i) => i.value));
    const shown = rest > 0 ? [...top, { label: '기타', value: rest }] : top;
    const colored = shown.map((it, i) => ({ ...it, color: COLORS.palette[i % COLORS.palette.length] }));
    body = `<div class="dist">${donut(colored, { top: fmtInt(total), bottom: '최근 28일' })}
      <ul class="dlegend">${colored.map((c) => `<li><i style="background:${c.color}"></i><span class="n">${esc(c.label)}</span><span class="v">${fmtInt(c.value)}</span><span class="p">${fmtPct(total ? c.value / total : 0, 0)}</span></li>`).join('')}</ul></div>`;
  }
  return `<section class="card span-5"><div class="card-h"><div><h2>사용자 분포</h2><p>최근 28일 활성 사용자 기준</p></div></div>${tabs}${body}</section>`;
}

export function footerNote(docs) {
  const s = docs.summary;
  return `<div class="foot span-12">데이터 기준: Google Analytics 4 · 플레이 스토어 <b>출시 버전만</b> 집계(개발용 앱 제외)<br>
    마지막 동기화 ${esc(relTime(s.updatedAt))} · 데이터는 ${esc(s.latest ? fmtLong(s.latest) : '-')}까지 확정<br>
    구글 처리 지연 때문에 최근 1~2일 값은 나중에 조금 바뀔 수 있어요.${s.source === 'mock' ? '<br><b>※ 지금 보이는 건 데모(모의) 데이터입니다.</b>' : ''}</div>`;
}

export function skeleton() {
  const k = '<div class="kpi"><div class="sk" style="height:14px;width:60%"></div><div class="sk" style="height:34px;width:70%;margin:12px 0"></div><div class="sk" style="height:20px;width:50%"></div></div>';
  return `<main class="wrap"><div class="card insight span-12"><div class="sk" style="height:16px;width:40%;background:rgba(255,255,255,.25)"></div><div class="sk" style="height:18px;margin-top:12px;background:rgba(255,255,255,.2)"></div></div>
    <div class="kpis span-12">${k}${k}${k}${k}</div><div class="card span-12"><div class="sk" style="height:250px"></div></div></main>`;
}

// ───────────────────────── 차트 붙이기 ─────────────────────────

/** HTML을 넣은 뒤 호출. 만든 차트를 배열로 돌려줘서 다음 렌더 전에 destroy할 수 있게 한다. */
export function mountCharts(root, docs, view, ui) {
  const charts = [];
  const $ = (id) => root.querySelector(id);
  const money = docs.summary.currency ?? 'USD';

  if ($('#ch-users')) {
    charts.push(lineChart($('#ch-users'), {
      title: '활성 사용자 추이', dates: view.dates, height: 240, valueFmt: (v) => `${fmtInt(v)}명`,
      series: [
        { key: 'mau', label: 'MAU', color: COLORS.mau, values: view.cur('mau'), visible: ui.visible.mau },
        { key: 'wau', label: 'WAU', color: COLORS.wau, values: view.cur('wau'), visible: ui.visible.wau },
        { key: 'dau', label: 'DAU', color: COLORS.dau, values: view.cur('dau'), visible: ui.visible.dau, area: true },
      ],
    }));
  }
  if ($('#ch-installs')) {
    const b = bucketSize(view.len);
    const inst = bucketize(view.dates, view.cur('installs'), b, 'sum');
    const rem = bucketize(view.dates, view.cur('uninstalls'), b, 'sum');
    charts.push(barChart($('#ch-installs'), {
      title: '설치와 삭제', height: 206,
      labels: inst.dates.map((d) => fmtMD(d)),
      tips: inst.spans.map(([a, z]) => (a === z ? fmtLong(a) : `${fmtMD(a)} ~ ${fmtMD(z)}`)),
      groups: [{ key: 'i', label: '설치', color: COLORS.install, values: inst.values }, { key: 'u', label: '삭제', color: COLORS.uninstall, values: rem.values }],
      valueFmt: (v) => `${fmtInt(v)}건`,
    }));
  }
  if ($('#ch-sessions')) {
    charts.push(lineChart($('#ch-sessions'), {
      title: '세션 수', dates: view.dates, height: 176, valueFmt: (v) => `${fmtInt(v)}회`,
      series: [{ key: 's', label: '세션', color: COLORS.dau, values: view.cur('sessions'), area: true }],
    }));
  }
  if ($('#ch-ads')) {
    charts.push(lineChart($('#ch-ads'), {
      title: '광고 노출', dates: view.dates, height: 196, valueFmt: (v) => `${fmtInt(v)}회`,
      series: [{ key: 'imp', label: '노출', color: COLORS.ads, values: view.cur('adImpressions'), area: true }],
    }));
  }
  void money;
  return charts;
}

/** 이벤트 상세 시트(HTML). 차트는 시트를 붙인 뒤 mountEventChart로 그린다. */
export function eventSheet(docs, view, name) {
  const meta = eventMeta(name);
  const arr = eventRange(docs, view, name);
  const prev = view.hasPrev ? (docs.events.series[name] ?? []).slice(view.from - view.len, view.from) : [];
  const total = sum(arr); const peakIdx = arr.reduce((b, v, i) => (v > arr[b] ? i : b), 0);
  const d = view.hasPrev ? deltaInfo(total, sum(prev)) : { pct: null, dir: null };
  return `<div class="grab"></div><h3>${meta.icon} ${esc(meta.label)}</h3>
    <p class="lead">${esc(meta.desc ?? '최근 기간의 일별 사용 횟수예요.')}</p>
    <div class="evstats"><div class="stat"><b>${fmtInt(total)}회</b><span>${view.len}일 합계</span></div><div class="stat"><b>${(total / Math.max(1, view.len)).toFixed(1)}회</b><span>하루 평균</span></div><div class="stat"><b>${arr.length ? fmtMD(view.dates[peakIdx]) : '-'}</b><span>가장 많았던 날</span></div></div>
    <div style="margin:-4px 0 10px">${deltaChip(d)} <span class="sub">직전 ${view.len}일 대비</span></div>
    <div id="ch-event" style="min-height:190px"></div>
    <button class="btn ghost" data-action="close-sheet" style="margin-top:14px">닫기</button>`;
}

export function mountEventChart(root, docs, view, name) {
  const meta = eventMeta(name);
  const el = root.querySelector('#ch-event');
  if (!el) return null;
  return lineChart(el, {
    title: `${meta.label} 추이`, dates: view.dates, height: 196, valueFmt: (v) => `${fmtInt(v)}회`,
    series: [{ key: 'e', label: meta.label, color: COLORS.dau, values: eventRange(docs, view, name), area: true }],
  });
}
