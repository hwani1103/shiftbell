// admin_dashboard/public/assets/js/format.js - 숫자·날짜·기간 표시 도우미(한국어 기준)

const WEEKDAYS = ['일', '월', '화', '수', '목', '금', '토'];

const trim = (x) => {
  const r = Math.abs(x) >= 100 ? Math.round(x) : Math.round(x * 10) / 10;
  return String(r);
};

export const fmtInt = (n) => (Number.isFinite(n) ? Math.round(n).toLocaleString('ko-KR') : '-');

/** 1만 이상은 "1.2만", 1억 이상은 "1.5억"으로 줄인다. */
export function fmtCompact(n) {
  if (!Number.isFinite(n)) return '-';
  const a = Math.abs(n);
  if (a >= 1e8) return `${trim(n / 1e8)}억`;
  if (a >= 1e4) return `${trim(n / 1e4)}만`;
  return fmtInt(n);
}

export const fmtPct = (x, d = 1) => (Number.isFinite(x) ? `${(x * 100).toFixed(d).replace(/\.0+$/, '')}%` : '-');

export function fmtDur(sec) {
  if (!Number.isFinite(sec) || sec <= 0) return '0초';
  const s = Math.round(sec);
  if (s < 60) return `${s}초`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}분 ${s % 60}초`;
  return `${Math.floor(m / 60)}시간 ${m % 60}분`;
}

export function fmtMoney(v, currency = 'USD') {
  if (!Number.isFinite(v)) return '-';
  try {
    const digits = currency === 'KRW' || currency === 'JPY' ? 0 : 2;
    return new Intl.NumberFormat('ko-KR', { style: 'currency', currency, minimumFractionDigits: digits, maximumFractionDigits: digits }).format(v);
  } catch {
    return `${v.toFixed(2)} ${currency}`;
  }
}

export function parseYmd(s) {
  const [y, m, d] = s.split('-').map(Number);
  return { y, m, d, wd: new Date(Date.UTC(y, m - 1, d)).getUTCDay() };
}
export const fmtMD = (s) => { const p = parseYmd(s); return `${p.m}/${p.d}`; };
export const fmtMonth = (s) => `${parseYmd(s).m}월`;
export const fmtLong = (s) => { const p = parseYmd(s); return `${p.m}월 ${p.d}일 (${WEEKDAYS[p.wd]})`; };
export const fmtFull = (s) => { const p = parseYmd(s); return `${p.y}년 ${p.m}월 ${p.d}일 (${WEEKDAYS[p.wd]})`; };

/** "3분 전", "2시간 전", "어제" 식 상대 시간. */
export function relTime(iso, now = Date.now()) {
  const t = Date.parse(iso);
  if (!Number.isFinite(t)) return '-';
  const diff = Math.max(0, now - t) / 1000;
  if (diff < 60) return '방금 전';
  if (diff < 3600) return `${Math.floor(diff / 60)}분 전`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}시간 전`;
  const d = Math.floor(diff / 86400);
  return d === 1 ? '어제' : `${d}일 전`;
}

/** 현재 값 vs 이전 값 → { pct, dir: 'up'|'down'|'flat'|'new'|null } */
export function deltaInfo(cur, prev) {
  if (!Number.isFinite(cur) || !Number.isFinite(prev)) return { pct: null, dir: null };
  if (prev === 0) return cur > 0 ? { pct: null, dir: 'new' } : { pct: 0, dir: 'flat' };
  const pct = (cur - prev) / prev;
  if (Math.abs(pct) < 0.0005) return { pct: 0, dir: 'flat' };
  return { pct, dir: pct > 0 ? 'up' : 'down' };
}

export const sum = (a) => a.reduce((x, y) => x + y, 0);
export const avg = (a) => (a.length ? sum(a) / a.length : 0);

/** 배열을 size개씩 묶어 sum/avg/last로 줄인다. 마지막 묶음이 모자라도 그대로 둔다. */
export function bucketize(dates, values, size, mode = 'sum') {
  if (size <= 1) return { dates: dates.slice(), values: values.slice(), spans: dates.map((d) => [d, d]) };
  const outD = []; const outV = []; const spans = [];
  for (let i = 0; i < values.length; i += size) {
    const chunk = values.slice(i, i + size);
    outD.push(dates[i]);
    spans.push([dates[i], dates[Math.min(i + size, dates.length) - 1]]);
    outV.push(mode === 'avg' ? avg(chunk) : mode === 'last' ? chunk[chunk.length - 1] : sum(chunk));
  }
  return { dates: outD, values: outV, spans };
}

export const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
