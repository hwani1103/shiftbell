import { withStream } from './ga4.mjs';
import { reportRows, shiftDate, retentionQuery, parseRetention } from './growth.mjs';
import { reportState } from './operations.mjs';
import { FEATURE_NAMES } from '../../public/assets/js/pulse-model.js';

const dims = names => names.map(name => ({ name }));
const ymd = raw => /^\d{8}$/.test(raw) ? `${raw.slice(0,4)}-${raw.slice(4,6)}-${raw.slice(6)}` : raw;
export function newcomersQuery(streamId, from, to) {
  return { dateRanges: [{ startDate: from, endDate: to }],
    dimensions: dims(['firstSessionDate', 'country', 'language', 'eventName']),
    metrics: dims(['totalUsers', 'eventCount']),
    dimensionFilter: withStream(streamId, { andGroup: { expressions: [
      { filter: { fieldName: 'firstSessionDate', betweenFilter: { fromValue: { int64Value: from.replaceAll('-', '') }, toValue: { int64Value: to.replaceAll('-', '') } } } },
      { filter: { fieldName: 'eventName', inListFilter: { values: ['first_open', 'onboarding_complete', ...FEATURE_NAMES] } } },
    ] } }), limit: '10000',
  };
}
export function retentionTrendQuery(streamId, latest) {
  const base = retentionQuery(streamId, latest, 7);
  base.cohortSpec.cohorts = Array.from({ length: 8 }, (_, i) => {
    const snapshot = shiftDate(latest, -7 + i), to = shiftDate(snapshot, -7);
    return { name: `d${snapshot.replaceAll('-', '')}`, dimension: 'firstSessionDate',
      dateRange: { startDate: shiftDate(to, -6), endDate: to } };
  });
  return base;
}
export function newcomerRows(report) {
  if (!report) return null;
  const groups = new Map();
  for (const r of reportRows(report)) {
    if (!/^\d{8}$/.test(r.firstSessionDate)) continue;
    const date = ymd(r.firstSessionDate), country = r.country || '(missing)', language = r.language || '(missing)';
    const key = JSON.stringify([date, country, language]);
    if (!groups.has(key)) groups.set(key, { date, country, language, firstOpens: 0, completed: 0, features: {} });
    const row = groups.get(key);
    if (r.eventName === 'first_open') row.firstOpens = r.totalUsers;
    else if (r.eventName === 'onboarding_complete') row.completed = r.totalUsers;
    else if (FEATURE_NAMES.includes(r.eventName)) row.features[r.eventName] = r.totalUsers;
  }
  return [...groups.values()].sort((a,b) => b.date.localeCompare(a.date) || b.firstOpens - a.firstOpens || a.country.localeCompare(b.country));
}
export function retentionTrend(report, latest) {
  if (!report) return null;
  const ci = report.dimensionHeaders.findIndex(h => h.name === 'cohort');
  return Array.from({ length: 8 }, (_, i) => {
    const date = shiftDate(latest, -7 + i), name = `d${date.replaceAll('-', '')}`;
    const rows = (report.rows ?? []).filter(r => r.dimensionValues[ci]?.value === name);
    return { date, ...parseRetention({ ...report, rows, rowCount: rows.length }, date, 7),
      // A truncated source must not become complete after selecting a cohort.
      ...(reportState(report).truncated ? { truncated: true, rate: null } : {}) };
  });
}
export async function fetchPulse(ga, now, latest, log = console) {
  const today = now.toLocaleDateString('en-CA', { timeZone: 'Asia/Seoul' });
  const from = shiftDate(today, -29);
  const requests = {
    core: { ...ga.coreDaily(30), dateRanges: [{ startDate: from, endDate: today }] },
    events: { ...ga.eventsDaily(30), dateRanges: [{ startDate: from, endDate: today }], metrics: dims(['eventCount', 'totalUsers']),
      dimensionFilter: withStream(ga.streamId, { filter: { fieldName: 'eventName', inListFilter: { values: FEATURE_NAMES } } }) },
    newcomers: newcomersQuery(ga.streamId, from, today),
    retention: retentionTrendQuery(ga.streamId, latest),
  };
  const reports = {};
  for (const [key, request] of Object.entries(requests)) reports[key] = await ga.tryReport(`daily/${key}`, request, log);
  const coverage = Object.fromEntries(Object.entries(reports).map(([k,r]) => [k,reportState(r)]));
  const doc = { schema: 1, updatedAt: now.toISOString(), today, from,
    timezone: reports.core?.metadata?.timeZone ?? 'Asia/Seoul', coverage,
    daily: reports.core ? reportRows(reports.core).map(r => ({ date: ymd(r.date), dau: r.active1DayUsers, newUsers: r.newUsers })) : null,
    events: reports.events ? reportRows(reports.events).map(r => ({ date: ymd(r.date), name: r.eventName, count: r.eventCount, users: r.totalUsers })) : null,
    newcomers: newcomerRows(reports.newcomers), retention: retentionTrend(reports.retention, latest) };
  // Keep this optional report below the single-document limit without breaking core sync.
  if (Buffer.byteLength(JSON.stringify(doc)) > 800000) {
    doc.newcomers = null;
    doc.coverage.newcomers = { status: 'unavailable', reason: 'size-limit' };
  }
  log.log('Daily overview: ' + JSON.stringify({ today, states: coverage, newcomerGroups: doc.newcomers?.length ?? null }));
  return doc;
}
