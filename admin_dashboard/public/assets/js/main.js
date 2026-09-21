// admin_dashboard/public/assets/js/main.js - 로그인/대시보드 화면 전환과 이벤트 처리.

import {
  RANGES, ICONS, brandMark, computeView, kpiGrid, insightCard, usersCard, installsCard, engagementCard, retentionCard,
  adsCard, behaviorCard, distCard, footerNote, skeleton, mountCharts, eventSheet, mountEventChart,
} from './views.js';
import * as auth from './auth.js';
import { loadDocs } from './store.js';
import { esc, relTime, fmtLong } from './format.js';

const root = document.getElementById('app');
const layer = document.getElementById('layer');
const params = new URLSearchParams(location.search);
const isLocal = ['localhost', '127.0.0.1'].includes(location.hostname);
/** 로컬에서 ?demo 로 열 때만 모의 데이터(운영 주소에서는 절대 동작하지 않는다). */
const DEMO = isLocal && params.has('demo');

const store = {
  get: (k, d) => { try { return localStorage.getItem(k) ?? d; } catch { return d; } },
  set: (k, v) => { try { localStorage.setItem(k, v); } catch { /* 저장 불가 환경은 무시 */ } },
};

const ui = {
  range: RANGES.includes(Number(store.get('range'))) ? Number(store.get('range')) : 30,
  visible: { dau: true, wau: true, mau: true },
  dist: 'appVersion', evGroup: 'all', evSystem: false,
};
let docs = null; let user = null; let charts = []; let loading = false; let error = null; let loadedAt = 0; let sheetChart = null;

// ───────────────────────── 테마 ─────────────────────────
function applyTheme() {
  const t = store.get('theme', 'auto');
  if (t === 'auto') document.documentElement.removeAttribute('data-theme');
  else document.documentElement.setAttribute('data-theme', t);
  const dark = t === 'dark' || (t === 'auto' && matchMedia('(prefers-color-scheme: dark)').matches);
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', dark ? '#0a0e16' : '#f2f4fa');
}

// ───────────────────────── 공용 UI ─────────────────────────
function toast(text) {
  const el = document.createElement('div');
  el.className = 'toast'; el.setAttribute('role', 'status'); el.textContent = text;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 2600);
}

function closeSheet() {
  sheetChart?.destroy(); sheetChart = null;
  layer.innerHTML = '';
  document.body.style.overflow = '';
}
function openSheet(html, after) {
  layer.innerHTML = `<div class="scrim" data-action="close-sheet"></div><div class="sheet" role="dialog" aria-modal="true">${html}</div>`;
  document.body.style.overflow = 'hidden';
  after?.(layer.querySelector('.sheet'));
}
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && layer.firstChild) closeSheet(); });

const initialOf = (email) => (email ? email[0].toUpperCase() : '?');

// ───────────────────────── 로그인 ─────────────────────────
function renderLogin(message = '') {
  destroyCharts();
  root.innerHTML = `<div class="login"><form class="login-card" id="login" novalidate>
    <div class="brand">${brandMark}<div><h1>교대시계 관리자</h1><p>운영 현황 대시보드</p></div></div>
    ${message ? `<div class="msg err" role="alert">${esc(message)}</div>` : ''}
    <label class="field"><span>이메일</span><input class="input" type="email" name="email" autocomplete="username" inputmode="email" autocapitalize="off" spellcheck="false" placeholder="name@example.com" required value="${esc(store.get('lastEmail', ''))}"></label>
    <label class="field"><span>비밀번호</span><div class="pw"><input class="input" type="password" name="password" autocomplete="current-password" required><button type="button" data-action="togglepw" aria-label="비밀번호 보기">${ICONS.eye}</button></div></label>
    <label class="check"><input type="checkbox" name="remember" checked><span class="switch"></span>로그인 상태 유지</label>
    <button class="btn" type="submit">로그인</button>
    <p class="foot-note">관리자 전용 페이지예요</p></form></div>`;
  const form = root.querySelector('#login');
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const fd = new FormData(form);
    const email = String(fd.get('email') || '').trim(); const pw = String(fd.get('password') || '');
    if (!email || !pw) { renderLogin('이메일과 비밀번호를 입력해 주세요.'); return; }
    const btn = form.querySelector('.btn');
    btn.disabled = true; btn.innerHTML = '<span class="spin"></span>로그인 중';
    try {
      store.set('lastEmail', email);
      await auth.signIn(email, pw, fd.get('remember') === 'on');
    } catch (err) {
      renderLogin(auth.authMessage(err));
      root.querySelector('input[name="email"]').value = email;
      root.querySelector('input[name="password"]').focus();
    }
  });
}

// ───────────────────────── 대시보드 ─────────────────────────
function destroyCharts() { charts.forEach((c) => c.destroy()); charts = []; }

function headerHtml(view) {
  const s = docs?.summary;
  const stale = s ? Date.now() - Date.parse(s.updatedAt) > 36 * 3600 * 1000 : false;
  const latest = s?.latest ? fmtLong(s.latest) : '-';
  return `<header class="topbar"><div class="wrap">
    <div class="bar1">${brandMark}<div class="titles"><b>교대시계 관리자</b><small>Play 출시 버전 · ${esc(latest)}까지 확정</small></div>
      <button class="icon-btn${loading ? ' spinning' : ''}" data-action="refresh" aria-label="새로고침">${ICONS.refresh}</button>
      <button class="avatar" data-action="menu" aria-label="계정 메뉴">${esc(initialOf(user?.email))}</button></div>
    <div class="bar2"><div class="seg" role="group" aria-label="조회 기간">${RANGES.map((r) => `<button data-action="range" data-key="${r}" aria-pressed="${ui.range === r}">${r}일</button>`).join('')}</div>
      <span class="pill${stale ? ' warn' : ''}" title="마지막 동기화"><span class="dot"></span>${s ? esc(relTime(s.updatedAt)) : '-'}</span></div>
  </div></header>`;
}

function emptyState(icon, title, body, action = '') {
  return `<main class="wrap"><section class="card span-12"><div class="empty"><div class="em">${icon}</div><b>${title}</b><p>${body}</p>${action}</div></section></main>`;
}

function renderApp() {
  destroyCharts();
  if (error) {
    const denied = error.code === 'permission-denied';
    const nodata = error.code === 'no-data';
    root.innerHTML = `<header class="topbar"><div class="wrap"><div class="bar1">${brandMark}<div class="titles"><b>교대시계 관리자</b></div><button class="avatar" data-action="menu" aria-label="계정 메뉴">${esc(initialOf(user?.email))}</button></div></div></header>` +
      emptyState(denied ? '🔒' : nodata ? '⏳' : '📡',
        denied ? '이 계정은 열람 권한이 없어요' : nodata ? '아직 동기화된 데이터가 없어요' : '데이터를 불러오지 못했어요',
        denied ? '관리자로 지정된 계정으로 로그인해 주세요.' : nodata ? '데이터 동기화(sync)를 한 번 실행하면 이 화면이 채워져요. 자세한 방법은 admin_dashboard/README.md를 참고하세요.' : esc(error.message ?? ''),
        `<div style="margin-top:16px"><button class="btn sm" data-action="refresh">다시 불러오기</button></div>`);
    return;
  }
  if (!docs) { root.innerHTML = skeleton(); return; }
  const y = window.scrollY;
  const view = computeView(docs, ui.range);
  if (!view.n) {
    root.innerHTML = headerHtml(view) + emptyState('🌱', '아직 집계된 날짜가 없어요', '출시된 버전에서 앱이 실행되면 하루 이내에 데이터가 들어와요.');
    return;
  }
  root.innerHTML = headerHtml(view) + `<main class="wrap">
    ${insightCard(docs, view)}${kpiGrid(docs, view).replace('<section class="kpis"', '<section class="kpis span-12"')}
    ${usersCard(view, ui.visible)}${installsCard(view)}
    ${behaviorCard(docs, view, ui)}${distCard(docs, ui)}
    ${engagementCard(view)}${retentionCard(docs)}
    ${adsCard(docs, view)}${footerNote(docs)}</main>`;
  charts = mountCharts(root, docs, view, ui);
  window.scrollTo(0, y);
}

async function loadData() {
  if (loading) return;
  loading = true; error = null;
  root.querySelector('[data-action="refresh"]')?.classList.add('spinning');
  try {
    docs = await loadDocs({ demo: DEMO });
    loadedAt = Date.now();
  } catch (e) {
    error = e; if (e.code !== 'no-data' && e.code !== 'permission-denied') console.error(e);
  } finally {
    loading = false;
  }
  renderApp();
}

// ───────────────────────── 계정 메뉴 / 비밀번호 변경 ─────────────────────────
function openMenu() {
  const t = store.get('theme', 'auto');
  openSheet(`<div class="grab"></div>
    <div class="who"><div class="avatar">${esc(initialOf(user?.email))}</div><div><b>${esc(user?.email ?? '')}</b><span>${DEMO ? '데모 모드' : '관리자'}</span></div></div>
    <div class="menu-list">
      <div class="menu-item" style="cursor:default"><span class="mi">🎨</span>화면 테마</div>
      <div class="themeseg">${[['auto', '자동'], ['light', '라이트'], ['dark', '다크']].map(([k, l]) => `<button data-action="theme" data-key="${k}" aria-pressed="${t === k}">${l}</button>`).join('')}</div>
      ${DEMO ? '' : '<button class="menu-item" data-action="pwd"><span class="mi">🔑</span>비밀번호 변경</button>'}
      ${DEMO ? '' : '<button class="menu-item danger" data-action="logout"><span class="mi">🚪</span>로그아웃</button>'}
    </div>`);
}

function openPassword() {
  openSheet(`<div class="grab"></div><h3>비밀번호 변경</h3><p class="lead">보안을 위해 현재 비밀번호를 한 번 더 확인해요.</p>
    <form id="pwform" novalidate><div id="pwmsg"></div>
      <label class="field"><span>현재 비밀번호</span><input class="input" type="password" name="cur" autocomplete="current-password" required></label>
      <label class="field"><span>새 비밀번호 (6자 이상)</span><input class="input" type="password" name="next" autocomplete="new-password" minlength="6" required></label>
      <label class="field"><span>새 비밀번호 확인</span><input class="input" type="password" name="again" autocomplete="new-password" required></label>
      <button class="btn" type="submit">변경하기</button>
      <button class="btn ghost" type="button" data-action="close-sheet" style="margin-top:10px">취소</button></form>`,
  (sheet) => {
    const form = sheet.querySelector('#pwform'); const msg = sheet.querySelector('#pwmsg');
    const show = (text) => { msg.innerHTML = `<div class="msg err" role="alert">${esc(text)}</div>`; };
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const fd = new FormData(form); const cur = String(fd.get('cur')); const next = String(fd.get('next')); const again = String(fd.get('again'));
      if (!cur) return show('현재 비밀번호를 입력해 주세요.');
      if (next.length < 6) return show('새 비밀번호는 6자 이상이어야 해요.');
      if (next !== again) return show('새 비밀번호 확인이 일치하지 않아요.');
      if (next === cur) return show('현재와 같은 비밀번호는 쓸 수 없어요.');
      const btn = form.querySelector('.btn'); btn.disabled = true; btn.innerHTML = '<span class="spin"></span>변경 중';
      try {
        await auth.changePassword(cur, next);
        closeSheet(); toast('비밀번호를 변경했어요');
      } catch (err) {
        btn.disabled = false; btn.textContent = '변경하기';
        show(auth.authMessage(err));
      }
    });
    form.querySelector('input[name="cur"]').focus();
  });
}

// ───────────────────────── 이벤트 위임 ─────────────────────────
function handle(action, el) {
  switch (action) {
    case 'range': ui.range = Number(el.dataset.key); store.set('range', String(ui.range)); renderApp(); break;
    case 'legend': {
      const k = el.dataset.key;
      const on = Object.values(ui.visible).filter(Boolean).length;
      if (ui.visible[k] && on <= 1) break; // 최소 하나는 켜 둔다
      ui.visible[k] = !ui.visible[k]; renderApp(); break;
    }
    case 'dist': ui.dist = el.dataset.key; renderApp(); break;
    case 'evgroup': ui.evGroup = el.dataset.key; renderApp(); break;
    case 'evsystem': ui.evSystem = !ui.evSystem; renderApp(); break;
    case 'event': {
      const view = computeView(docs, ui.range);
      openSheet(eventSheet(docs, view, el.dataset.event), (sheet) => { sheetChart = mountEventChart(sheet, docs, view, el.dataset.event); });
      break;
    }
    case 'refresh': loadData(); break;
    case 'menu': openMenu(); break;
    case 'pwd': closeSheet(); openPassword(); break;
    case 'logout': closeSheet(); auth.signOut(); break;
    case 'theme': store.set('theme', el.dataset.key); applyTheme(); openMenu(); break;
    case 'close-sheet': closeSheet(); break;
    case 'togglepw': {
      const input = el.closest('.pw').querySelector('input');
      input.type = input.type === 'password' ? 'text' : 'password'; break;
    }
    default: break;
  }
}
function onActivate(e) {
  const el = e.target.closest('[data-action]');
  if (!el) return;
  handle(el.dataset.action, el);
}
root.addEventListener('click', onActivate);
layer.addEventListener('click', onActivate);
root.addEventListener('keydown', (e) => {
  if ((e.key === 'Enter' || e.key === ' ') && e.target.matches?.('[data-action="event"]')) { e.preventDefault(); onActivate(e); }
});

// 화면으로 돌아왔을 때 10분 넘게 지났으면 자동으로 다시 불러온다.
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible' && user && docs && Date.now() - loadedAt > 10 * 60 * 1000) loadData();
});
matchMedia('(prefers-color-scheme: dark)').addEventListener?.('change', applyTheme);

// ───────────────────────── 시작 ─────────────────────────
function fatal(text) {
  root.innerHTML = `<div class="login"><div class="login-card"><div class="brand">${brandMark}<div><h1>교대시계 관리자</h1></div></div><div class="msg err">${esc(text)}</div></div></div>`;
}

applyTheme();
if (DEMO) {
  user = { email: 'demo@shiftbell.local' };
  root.innerHTML = skeleton();
  loadData();
} else if (!auth.available()) {
  fatal('Firebase를 불러오지 못했어요. 새로고침하거나 잠시 뒤에 다시 시도해 주세요.');
} else {
  auth.connectLocalEmulators();
  auth.watch((u) => {
    user = u;
    closeSheet();
    if (u) { docs = null; error = null; root.innerHTML = skeleton(); loadData(); } else { docs = null; renderLogin(); }
  });
}
