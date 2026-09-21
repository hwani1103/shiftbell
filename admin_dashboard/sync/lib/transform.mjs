// admin_dashboard/sync/lib/transform.mjs
//
// GA4 Data API 응답 → 대시보드가 읽는 Firestore 문서 3개(summary / series / events)로 바꾸는 순수 함수 모음.
// 네트워크·파일 접근이 전혀 없어서 test/transform.test.mjs에서 응답 fixture만으로 검증한다.
//
// 문서 스키마(schema: 1) - UI(public/assets/js)와 mock 생성기(public/assets/js/mock.js)가 같은 모양을 쓴다.
//   summary : 최신 KPI·분포·리텐션·이벤트 요약·플래그
//   series  : 날짜 배열 + 날짜별 지표 배열들(최대 400일)
//   events  : 날짜 배열 + 이벤트별 일별 횟수(상위 N개)

export const SCHEMA = 1;

/** 구글이 자동 수집하는 이벤트(사용자 정의 이벤트 여부 판단용). */
export const AUTO_EVENTS = new Set([
  'first_open', 'session_start', 'screen_view', 'user_engagement', 'app_remove', 'app_update', 'os_update',
  'app_clear_data', 'app_exception', 'ad_impression', 'ad_click', 'notification_receive', 'notification_open',
  'notification_foreground', 'notification_dismiss', 'first_visit', 'page_view', 'scroll', 'click',
]);

/** 상위 N개 밖이어도 항상 보관할 이벤트(설치·삭제·광고 등 KPI에 쓰이는 것). */
export const ALWAYS_KEEP = ['first_open', 'app_remove', 'session_start', 'screen_view', 'ad_impression'];

/** 'YYYYMMDD' → 'YYYY-MM-DD' */
export function ymd(s) {
  const v = String(s);
  return v.length === 8 ? `${v.slice(0, 4)}-${v.slice(4, 6)}-${v.slice(6, 8)}` : v;
}

/** 응답 → [{ d: [dimension...], m: [metric(number)...] }] */
export function table(resp) {
  if (!resp || !Array.isArray(resp.rows)) return [];
  return resp.rows.map((r) => ({
    d: (r.dimensionValues ?? []).map((x) => x.value),
    m: (r.metricValues ?? []).map((x) => Number(x.value) || 0),
  }));
}

/** 응답의 metricHeaders 이름 → 열 번호. */
function metricIndex(resp) {
  const map = {};
  (resp?.metricHeaders ?? []).forEach((h, i) => { map[h.name] = i; });
  return map;
}

const num = (v) => (Number.isFinite(v) ? v : 0);
const round = (v, digits = 0) => { const p = 10 ** digits; return Math.round(num(v) * p) / p; };

/** 일별 시리즈. 핵심 지표는 core 응답의 날짜를 기준으로 삼고, 나머지는 같은 날짜 축에 맞춰 채운다. */
export function buildSeries({ core, ads, eventsDaily }) {
  const rows = table(core);
  const idx = metricIndex(core);
  const dates = rows.map((r) => ymd(r.d[0]));
  const pos = new Map(dates.map((d, i) => [d, i]));
  const zeros = () => new Array(dates.length).fill(0);
  const col = (name) => rows.map((r) => (idx[name] == null ? 0 : r.m[idx[name]]));

  const series = {
    schema: SCHEMA,
    dates,
    dau: col('active1DayUsers'),
    wau: col('active7DayUsers'),
    mau: col('active28DayUsers'),
    newUsers: col('newUsers'),
    sessions: col('sessions'),
    engagementSec: col('userEngagementDuration'),
    installs: zeros(),
    uninstalls: zeros(),
    adImpressions: zeros(),
    adClicks: zeros(),
    adRevenue: zeros(),
  };

  for (const r of table(eventsDaily)) {
    const i = pos.get(ymd(r.d[0]));
    if (i == null) continue;
    if (r.d[1] === 'first_open') series.installs[i] += r.m[0];
    else if (r.d[1] === 'app_remove') series.uninstalls[i] += r.m[0];
  }

  let adsAvailable = false;
  if (ads) {
    const aIdx = metricIndex(ads);
    for (const r of table(ads)) {
      const i = pos.get(ymd(r.d[0]));
      if (i == null) continue;
      series.adImpressions[i] = r.m[aIdx.publisherAdImpressions ?? 0] ?? 0;
      series.adClicks[i] = r.m[aIdx.publisherAdClicks ?? 1] ?? 0;
      series.adRevenue[i] = round(r.m[aIdx.totalAdRevenue ?? 2] ?? 0, 4);
    }
    adsAvailable = series.adImpressions.some((v) => v > 0);
  }
  // 광고 노출 이벤트로도 보완(지표가 0이어도 ad_impression 이벤트가 오는 경우)
  if (!adsAvailable) {
    const fromEvents = zeros();
    for (const r of table(eventsDaily)) {
      const i = pos.get(ymd(r.d[0]));
      if (i != null && r.d[1] === 'ad_impression') fromEvents[i] += r.m[0];
    }
    if (fromEvents.some((v) => v > 0)) { series.adImpressions = fromEvents; adsAvailable = true; }
  }
  return { series, adsAvailable };
}

/** 이벤트별 일별 횟수(상위 keep개 + 항상 보관 목록). */
export function buildEvents({ eventsDaily, dates, keep = 40 }) {
  const pos = new Map(dates.map((d, i) => [d, i]));
  const byName = new Map();
  for (const r of table(eventsDaily)) {
    const i = pos.get(ymd(r.d[0]));
    if (i == null) continue;
    const name = r.d[1];
    if (!byName.has(name)) byName.set(name, new Array(dates.length).fill(0));
    byName.get(name)[i] += r.m[0];
  }
  const totals = [...byName.entries()].map(([name, arr]) => [name, arr.reduce((a, b) => a + b, 0)]);
  totals.sort((a, b) => b[1] - a[1]);
  const chosen = new Set(totals.slice(0, keep).map(([n]) => n));
  ALWAYS_KEEP.forEach((n) => { if (byName.has(n)) chosen.add(n); });
  const out = { schema: SCHEMA, dates, series: {}, totals: {} };
  for (const [name, total] of totals) {
    if (!chosen.has(name)) continue;
    out.series[name] = byName.get(name);
    out.totals[name] = total;
  }
  return out;
}

/** 최근 30일 이벤트 요약. */
export function buildEventSummary(resp) {
  return table(resp).map((r) => ({ name: r.d[0], count: r.m[0], users: r.m[1] }));
}

/** 분포(앱 버전·OS·언어·국가·기기) → [{name, users}] */
export function buildBreakdown(resp) {
  return table(resp)
    .filter((r) => r.d[0] && r.d[0] !== '(not set)')
    .map((r) => ({ name: r.d[0], users: r.m[0] }));
}

/** 코호트 응답 → { size, days:[0..1 비율], from, to } (표본이 없으면 null). */
export function buildCohort(resp, { from, to }) {
  const rows = table(resp);
  if (!rows.length) return null;
  const byDay = new Map(rows.map((r) => [parseInt(r.d[1], 10), r.m[0]]));
  const size = byDay.get(0) ?? 0;
  if (size <= 0) return null;
  const maxDay = Math.max(...byDay.keys());
  const days = [];
  for (let n = 0; n <= maxDay; n += 1) days.push(round((byDay.get(n) ?? 0) / size, 4));
  return { size, days, from, to };
}

/** 마지막 날 값과 최근 합계로 KPI를 계산한다. */
export function buildKpi(series) {
  const n = series.dates.length;
  if (!n) return null;
  const i = n - 1;
  const dau = series.dau[i];
  const mau = series.mau[i];
  return {
    dau,
    wau: series.wau[i],
    mau,
    stickiness: mau > 0 ? round(dau / mau, 4) : 0,
    newUsers: series.newUsers[i],
    installs: series.installs[i],
    uninstalls: series.uninstalls[i],
    sessions: series.sessions[i],
    sessionsPerUser: dau > 0 ? round(series.sessions[i] / dau, 2) : 0,
    engagementSecPerUser: dau > 0 ? round(series.engagementSec[i] / dau, 0) : 0,
  };
}

/** 전체 문서 세트를 만든다. raw는 ga4.mjs 리포트 응답 모음. */
export function buildDocs({ raw, meta }) {
  const { series, adsAvailable } = buildSeries({ core: raw.core, ads: raw.ads, eventsDaily: raw.eventsDaily });
  const events = buildEvents({ eventsDaily: raw.eventsDaily, dates: series.dates });
  const eventSummary = buildEventSummary(raw.eventsSummary);
  const hasCustomEvents = Object.keys(events.series).some((n) => !AUTO_EVENTS.has(n) && !n.startsWith('firebase_'));
  const summary = {
    schema: SCHEMA,
    updatedAt: meta.now.toISOString(),
    propertyId: meta.propertyId,
    streamId: meta.streamId,
    source: meta.source ?? 'ga4',
    range: { start: series.dates[0] ?? null, end: series.dates[series.dates.length - 1] ?? null },
    latest: series.dates[series.dates.length - 1] ?? null,
    kpi: buildKpi(series),
    cohort: raw.cohort ? buildCohort(raw.cohort, meta.cohortRange) : null,
    breakdowns: {
      appVersion: buildBreakdown(raw.appVersion),
      os: buildBreakdown(raw.os),
      language: buildBreakdown(raw.language),
      country: buildBreakdown(raw.country),
      device: buildBreakdown(raw.device),
    },
    events: eventSummary,
    flags: { ads: adsAvailable, customEvents: hasCustomEvents },
  };
  return { summary, series, events };
}
