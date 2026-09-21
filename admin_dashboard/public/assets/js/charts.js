// admin_dashboard/public/assets/js/charts.js
//
// 의존성 없는 SVG 차트 엔진. 모바일에서 가볍고, 터치로 좌우로 훑으면 툴팁이 따라오게 만들었다.
//   lineChart  : 부드러운 곡선(단조 3차 보간) + 면적 그라데이션 + 십자선 툴팁
//   barChart   : 묶음 막대 + 툴팁
//   sparkline  : KPI 카드용 미니 추이
//   donut      : 도넛 + 가운데 합계
//   hbarList   : 가로 막대 랭킹(HTML)
// 색은 CSS 변수(--c-*)가 아니라 호출부가 hex로 넘긴다 → 라이트/다크에서 같은 의미 색을 유지.

import { fmtCompact, fmtMD, fmtMonth, fmtLong, esc } from './format.js';

let uid = 0;
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));

/** 보기 좋은 축 눈금. integer=true면 소수 눈금을 만들지 않는다(사용자 수·횟수용). */
export function niceScale(minV, maxV, target = 4, integer = false) {
  let max = maxV;
  if (!(max > minV)) max = minV + 1;
  const rough = (max - minV) / target;
  const pow = 10 ** Math.floor(Math.log10(rough));
  const norm = rough / pow;
  let step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10) * pow;
  if (integer) step = Math.max(1, step);
  const lo = Math.floor(minV / step) * step;
  const hi = Math.ceil(max / step) * step;
  const ticks = [];
  for (let v = lo; v <= hi + step / 2; v += step) ticks.push(Math.round(v * 1e9) / 1e9);
  return { min: lo, max: hi, step, ticks };
}

/** Fritsch–Carlson 단조 3차 보간: 값이 튀지 않고(오버슈트 없음) 매끈하다. */
export function smoothPath(pts) {
  const n = pts.length;
  if (n === 0) return '';
  const f = (v) => Math.round(v * 100) / 100;
  if (n === 1) return `M${f(pts[0][0])},${f(pts[0][1])}`;
  if (n === 2) return `M${f(pts[0][0])},${f(pts[0][1])}L${f(pts[1][0])},${f(pts[1][1])}`;
  const dx = []; const m = [];
  for (let i = 0; i < n - 1; i += 1) {
    dx[i] = pts[i + 1][0] - pts[i][0];
    m[i] = dx[i] === 0 ? 0 : (pts[i + 1][1] - pts[i][1]) / dx[i];
  }
  const t = new Array(n);
  t[0] = m[0]; t[n - 1] = m[n - 2];
  for (let i = 1; i < n - 1; i += 1) {
    if (m[i - 1] * m[i] <= 0) t[i] = 0;
    else {
      const w1 = 2 * dx[i] + dx[i - 1]; const w2 = dx[i] + 2 * dx[i - 1];
      t[i] = (w1 + w2) / (w1 / m[i - 1] + w2 / m[i]);
    }
  }
  let d = `M${f(pts[0][0])},${f(pts[0][1])}`;
  for (let i = 0; i < n - 1; i += 1) {
    const c1x = pts[i][0] + dx[i] / 3; const c1y = pts[i][1] + (t[i] * dx[i]) / 3;
    const c2x = pts[i + 1][0] - dx[i] / 3; const c2y = pts[i + 1][1] - (t[i + 1] * dx[i]) / 3;
    d += `C${f(c1x)},${f(c1y)} ${f(c2x)},${f(c2y)} ${f(pts[i + 1][0])},${f(pts[i + 1][1])}`;
  }
  return d;
}

/** x축 라벨 위치(인덱스)와 문구. 긴 기간은 매월 1일 기준 "N월"로 보여 준다. */
function xLabels(dates, innerW) {
  const n = dates.length;
  const maxLabels = Math.max(2, Math.floor(innerW / 58));
  if (n > 120) {
    const idx = [];
    dates.forEach((d, i) => { if (d.slice(8) === '01') idx.push(i); });
    const step = Math.max(1, Math.ceil(idx.length / maxLabels));
    return idx.filter((_, k) => k % step === 0).map((i) => ({ i, text: fmtMonth(dates[i]) }));
  }
  if (n <= maxLabels) return dates.map((d, i) => ({ i, text: fmtMD(d) }));
  const step = Math.ceil((n - 1) / (maxLabels - 1));
  const out = [];
  for (let i = 0; i < n; i += step) out.push({ i, text: fmtMD(dates[i]) });
  return out;
}

function placeTip(tip, host, x) {
  tip.hidden = false;
  const w = tip.offsetWidth;
  const left = clamp(x - w / 2, 4, Math.max(4, host.clientWidth - w - 4));
  tip.style.left = `${left}px`;
}

/**
 * 선/면적 차트.
 * opt: { dates, series:[{key,label,color,values,area?,dash?,visible?}], height?, integer?, yFmt?, valueFmt?, title? }
 * 반환: { update(nextOpt), destroy() }
 */
export function lineChart(el, opt) {
  let o = opt;
  let first = true;
  el.classList.add('chart');

  function draw() {
    const W = Math.max(260, Math.round(el.clientWidth || 320));
    const H = o.height ?? 224;
    const m = { l: 40, r: 12, t: 14, b: 26 };
    const iw = W - m.l - m.r; const ih = H - m.t - m.b;
    const n = o.dates.length;
    const vis = o.series.filter((s) => s.visible !== false);
    let maxV = 0;
    vis.forEach((s) => s.values.forEach((v) => { if (v > maxV) maxV = v; }));
    const sc = niceScale(0, maxV * 1.06 || 1, 4, o.integer !== false);
    const X = (i) => m.l + (n <= 1 ? iw / 2 : (i / (n - 1)) * iw);
    const Y = (v) => m.t + ih - ((v - sc.min) / (sc.max - sc.min)) * ih;
    const yFmt = o.yFmt ?? fmtCompact;
    const id = `lc${(uid += 1)}`;

    let svg = `<svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="${esc(o.title ?? '추이 차트')}">`;
    svg += '<defs>';
    vis.forEach((s, k) => {
      if (s.area) {
        svg += `<linearGradient id="${id}-${k}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${s.color}" stop-opacity="0.30"/><stop offset="1" stop-color="${s.color}" stop-opacity="0"/></linearGradient>`;
      }
    });
    svg += '</defs>';
    // 격자 + y 라벨
    sc.ticks.forEach((t) => {
      const y = Y(t);
      svg += `<line class="grid" x1="${m.l}" y1="${y}" x2="${W - m.r}" y2="${y}"/><text class="ylab" x="${m.l - 8}" y="${y + 4}" text-anchor="end">${esc(yFmt(t))}</text>`;
    });
    // x 라벨
    xLabels(o.dates, iw).forEach(({ i, text }) => {
      svg += `<text class="xlab" x="${X(i)}" y="${H - 6}" text-anchor="${i === 0 ? 'start' : i === n - 1 ? 'end' : 'middle'}">${esc(text)}</text>`;
    });
    // 시리즈
    vis.forEach((s, k) => {
      const pts = s.values.map((v, i) => [X(i), Y(v)]);
      const line = smoothPath(pts);
      if (s.area && n > 1) {
        svg += `<path d="${line}L${X(n - 1)},${Y(0)}L${X(0)},${Y(0)}Z" fill="url(#${id}-${k})" class="area"/>`;
      }
      svg += `<path class="line${first ? ' draw' : ''}" d="${line}" pathLength="1" stroke="${s.color}"${s.dash ? ` stroke-dasharray="${s.dash}"` : ''}/>`;
      if (n >= 1) {
        const [lx, ly] = pts[n - 1];
        svg += `<circle class="endring" cx="${lx}" cy="${ly}" r="6" fill="${s.color}" opacity="0.18"/><circle class="enddot" cx="${lx}" cy="${ly}" r="3.2" fill="${s.color}"/>`;
      }
    });
    // 십자선/점(호버 시 위치만 바꾼다)
    svg += `<line class="xh" x1="0" y1="${m.t}" x2="0" y2="${m.t + ih}" style="display:none"/>`;
    vis.forEach((s, k) => { svg += `<circle class="pt" data-k="${k}" r="4.5" fill="var(--surface)" stroke="${s.color}" stroke-width="2.2" style="display:none"/>`; });
    svg += `<rect class="hit" x="${m.l}" y="0" width="${iw}" height="${H}" fill="transparent"/></svg><div class="tip" hidden></div>`;
    el.innerHTML = svg;
    first = false;

    const tip = el.querySelector('.tip');
    const xh = el.querySelector('.xh');
    const pts = [...el.querySelectorAll('.pt')];
    const hit = el.querySelector('.hit');
    const show = (ev) => {
      if (n === 0) return;
      const r = el.getBoundingClientRect();
      const px = ev.clientX - r.left;
      const i = clamp(Math.round(((px - m.l) / iw) * (n - 1)), 0, n - 1);
      const x = X(i);
      xh.setAttribute('x1', x); xh.setAttribute('x2', x); xh.style.display = '';
      let rows = '';
      pts.forEach((p, k) => {
        const s = vis[k];
        p.setAttribute('cx', x); p.setAttribute('cy', Y(s.values[i])); p.style.display = '';
        rows += `<div class="tr"><i style="background:${s.color}"></i><span>${esc(s.label)}</span><b>${esc((o.valueFmt ?? ((v) => v.toLocaleString('ko-KR')))(s.values[i]))}</b></div>`;
      });
      tip.innerHTML = `<div class="td">${esc(fmtLong(o.dates[i]))}</div>${rows}`;
      placeTip(tip, el, x);
    };
    const hide = () => { xh.style.display = 'none'; pts.forEach((p) => { p.style.display = 'none'; }); tip.hidden = true; };
    hit.addEventListener('pointermove', show);
    hit.addEventListener('pointerdown', show);
    hit.addEventListener('pointerleave', hide);
    hit.addEventListener('pointercancel', hide);
  }

  const ro = new ResizeObserver(() => { if (el.isConnected) draw(); });
  ro.observe(el);
  draw();
  return {
    update(next) { o = { ...o, ...next }; first = false; draw(); },
    destroy() { ro.disconnect(); },
  };
}

/**
 * 묶음 막대 차트.
 * opt: { labels:[표시문구], tips:[툴팁 제목], groups:[{key,label,color,values}], height?, integer?, valueFmt?, title? }
 */
export function barChart(el, opt) {
  let o = opt;
  el.classList.add('chart');

  function draw() {
    const W = Math.max(260, Math.round(el.clientWidth || 320));
    const H = o.height ?? 200;
    const m = { l: 40, r: 8, t: 12, b: 26 };
    const iw = W - m.l - m.r; const ih = H - m.t - m.b;
    const n = o.labels.length;
    let maxV = 0;
    o.groups.forEach((g) => g.values.forEach((v) => { if (v > maxV) maxV = v; }));
    const sc = niceScale(0, maxV * 1.06 || 1, 4, o.integer !== false);
    const Y = (v) => m.t + ih - ((v - sc.min) / (sc.max - sc.min)) * ih;
    const slot = n ? iw / n : iw;
    const gw = Math.min(slot * 0.72, 44);
    const bw = Math.max(2, (gw - (o.groups.length - 1) * 2) / o.groups.length);

    let svg = `<svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="${esc(o.title ?? '막대 차트')}">`;
    sc.ticks.forEach((t) => {
      const y = Y(t);
      svg += `<line class="grid" x1="${m.l}" y1="${y}" x2="${W - m.r}" y2="${y}"/><text class="ylab" x="${m.l - 8}" y="${y + 4}" text-anchor="end">${esc(fmtCompact(t))}</text>`;
    });
    const maxLabels = Math.max(2, Math.floor(iw / 50));
    const every = Math.max(1, Math.ceil(n / maxLabels));
    o.labels.forEach((l, i) => {
      if (i % every === 0) svg += `<text class="xlab" x="${m.l + slot * i + slot / 2}" y="${H - 6}" text-anchor="middle">${esc(l)}</text>`;
    });
    svg += '<rect class="hl" x="0" y="0" width="0" height="0" rx="6" style="display:none"/>';
    o.labels.forEach((_, i) => {
      const gx = m.l + slot * i + (slot - (bw * o.groups.length + (o.groups.length - 1) * 2)) / 2;
      o.groups.forEach((g, k) => {
        const v = g.values[i] ?? 0;
        if (v <= 0) return;
        const h = Math.max(2, (v / (sc.max - sc.min)) * ih);
        svg += `<rect class="bar" x="${gx + k * (bw + 2)}" y="${m.t + ih - h}" width="${bw}" height="${h}" rx="${Math.min(4, bw / 2)}" fill="${g.color}"/>`;
      });
    });
    svg += `<rect class="hit" x="${m.l}" y="0" width="${iw}" height="${H}" fill="transparent"/></svg><div class="tip" hidden></div>`;
    el.innerHTML = svg;

    const tip = el.querySelector('.tip'); const hl = el.querySelector('.hl'); const hit = el.querySelector('.hit');
    const show = (ev) => {
      if (!n) return;
      const r = el.getBoundingClientRect();
      const i = clamp(Math.floor((ev.clientX - r.left - m.l) / slot), 0, n - 1);
      const x = m.l + slot * i;
      hl.setAttribute('x', x + 1); hl.setAttribute('y', m.t); hl.setAttribute('width', slot - 2); hl.setAttribute('height', ih); hl.style.display = '';
      const rows = o.groups.map((g) => `<div class="tr"><i style="background:${g.color}"></i><span>${esc(g.label)}</span><b>${esc((o.valueFmt ?? ((v) => v.toLocaleString('ko-KR')))(g.values[i] ?? 0))}</b></div>`).join('');
      tip.innerHTML = `<div class="td">${esc(o.tips?.[i] ?? o.labels[i])}</div>${rows}`;
      placeTip(tip, el, x + slot / 2);
    };
    const hide = () => { hl.style.display = 'none'; tip.hidden = true; };
    hit.addEventListener('pointermove', show);
    hit.addEventListener('pointerdown', show);
    hit.addEventListener('pointerleave', hide);
    hit.addEventListener('pointercancel', hide);
  }

  const ro = new ResizeObserver(() => { if (el.isConnected) draw(); });
  ro.observe(el);
  draw();
  return { update(next) { o = { ...o, ...next }; draw(); }, destroy() { ro.disconnect(); } };
}

/** KPI 카드용 미니 추이(문자열 SVG). */
export function sparkline(values, color, { w = 92, h = 34 } = {}) {
  if (!values || values.length < 2) return `<svg class="spark" width="${w}" height="${h}" aria-hidden="true"></svg>`;
  const id = `sp${(uid += 1)}`;
  const max = Math.max(...values); const min = Math.min(...values);
  const span = max - min || 1;
  const pad = 3;
  const pts = values.map((v, i) => [pad + (i / (values.length - 1)) * (w - pad * 2), h - pad - ((v - min) / span) * (h - pad * 2)]);
  const line = smoothPath(pts);
  const [lx, ly] = pts[pts.length - 1];
  return `<svg class="spark" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" aria-hidden="true"><defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${color}" stop-opacity=".28"/><stop offset="1" stop-color="${color}" stop-opacity="0"/></linearGradient></defs><path d="${line}L${pts[pts.length - 1][0]},${h}L${pts[0][0]},${h}Z" fill="url(#${id})"/><path d="${line}" fill="none" stroke="${color}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><circle cx="${lx}" cy="${ly}" r="2.6" fill="${color}"/></svg>`;
}

/** 도넛(문자열 SVG). items: [{label,value,color}] */
export function donut(items, { size = 132, thickness = 18, top = '', bottom = '' } = {}) {
  const total = items.reduce((a, b) => a + b.value, 0);
  const r = (size - thickness) / 2; const C = 2 * Math.PI * r; const c = size / 2;
  let acc = 0;
  let segs = `<circle cx="${c}" cy="${c}" r="${r}" fill="none" stroke="var(--line)" stroke-width="${thickness}"/>`;
  if (total > 0) {
    items.forEach((it) => {
      if (it.value <= 0) return;
      const len = (it.value / total) * C;
      const gap = items.filter((x) => x.value > 0).length > 1 ? Math.min(3, len * 0.25) : 0;
      segs += `<circle cx="${c}" cy="${c}" r="${r}" fill="none" stroke="${it.color}" stroke-width="${thickness}" stroke-dasharray="${Math.max(0, len - gap)} ${C - Math.max(0, len - gap)}" stroke-dashoffset="${-acc}" transform="rotate(-90 ${c} ${c})"/>`;
      acc += len;
    });
  }
  return `<div class="donut" style="width:${size}px;height:${size}px"><svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" aria-hidden="true">${segs}</svg><div class="dc"><b>${esc(top)}</b><span>${esc(bottom)}</span></div></div>`;
}

/** 가로 막대 랭킹(HTML 문자열). items: [{label,value,display?,sub?,color?}] */
export function hbarList(items, { max, color = '#4662D6' } = {}) {
  const top = max ?? Math.max(1, ...items.map((i) => i.value));
  return `<ul class="hbars">${items.map((it) => {
    const pct = clamp((it.value / top) * 100, 0, 100);
    return `<li${it.attrs ? ` ${it.attrs}` : ''}><div class="hb-top"><span class="hb-l">${it.icon ? `<em>${it.icon}</em>` : ''}${esc(it.label)}</span><span class="hb-v">${esc(it.display ?? String(it.value))}</span></div><div class="hb-track"><i style="width:${pct}%;background:${it.color ?? color}"></i></div>${it.sub ? `<div class="hb-sub">${esc(it.sub)}</div>` : ''}</li>`;
  }).join('')}</ul>`;
}
