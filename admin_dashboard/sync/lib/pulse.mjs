import { withStream } from './ga4.mjs';
import { reportRows, shiftDate, retentionQuery, parseRetention } from './growth.mjs';
import { reportState } from './operations.mjs';
import { FEATURE_NAMES } from '../../public/assets/js/pulse-model.js';

const dims = names => names.map(name => ({ name }));
const ymd = raw => /^\d{8}$/.test(raw) ? `${raw.slice(0,4)}-${raw.slice(4,6)}-${raw.slice(6)}` : raw;
export function newcomersQuery(streamId, from, to) {
  const firstDates = [];
  for (let date = from; date <= to; date = shiftDate(date, 1)) firstDates.push(date.replaceAll('-', ''));
  return { dateRanges: [{ startDate: from, endDate: to }],
    dimensions: dims(['firstSessionDate', 'country', 'language', 'eventName']),
    metrics: dims(['totalUsers', 'eventCount']),
    dimensionFilter: withStream(streamId, { andGroup: { expressions: [
      { filter: { fieldName: 'firstSessionDate', inListFilter: { values: firstDates } } },
      { filter: { fieldName: 'eventName', inListFilter: { values: ['first_open', 'onboarding_complete', ...FEATURE_NAMES] } } },
    ] } }), limit: '10000',
  };
}
export function retentionTrendQuery(streamId, latest) {
  // Overlapping cohorts in ONE report assign a user to the first matching cohort.
  // Separate reports are required for comparable rolling seven-day populations.
  return Array.from({ length: 8 }, (_, i) => {
    const date = shiftDate(latest, -7 + i);
    return { date, query: retentionQuery(streamId, date, 7) };
  });
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
export function retentionTrend(reports) {
  return reports.map(({date, report}) => ({date, ...parseRetention(report, date, 7)}));
}
export async function fetchPulse(ga, now, latest, log = console) {
  const today = now.toLocaleDateString('en-CA', { timeZone: 'Asia/Seoul' });
  const from = shiftDate(today, -29);
  const requests = {
    core: { ...ga.coreDaily(30), dateRanges: [{ startDate: from, endDate: today }] },
    events: { ...ga.eventsDaily(30), dateRanges: [{ startDate: from, endDate: today }], metrics: dims(['eventCount', 'totalUsers']),
      dimensionFilter: withStream(ga.streamId, { filter: { fieldName: 'eventName', inListFilter: { values: FEATURE_NAMES } } }) },
    newcomers: newcomersQuery(ga.streamId, from, today),
  };
  const reports = {};
  for (const [key, request] of Object.entries(requests)) reports[key] = await ga.tryReport(`daily/${key}`, request, log);
  const retentionReports = [];
  for (const {date, query} of retentionTrendQuery(ga.streamId, latest)) {
    retentionReports.push({date, report: await ga.tryReport(`daily/retention/${date}`, query, log)});
  }
  const coverage = Object.fromEntries(Object.entries(reports).map(([k,r]) => [k,reportState(r)]));
  const doc = { schema: 1, updatedAt: now.toISOString(), today, from,
    timezone: reports.core?.metadata?.timeZone ?? 'Asia/Seoul', coverage,
    daily: reports.core ? reportRows(reports.core).map(r => ({ date: ymd(r.date), dau: r.active1DayUsers, newUsers: r.newUsers })) : null,
    events: reports.events ? reportRows(reports.events).map(r => ({ date: ymd(r.date), name: r.eventName, count: r.eventCount, users: r.totalUsers })) : null,
    newcomers: newcomerRows(reports.newcomers), retention: retentionTrend(retentionReports) };
  // Keep this optional report below the single-document limit without breaking core sync.
  if (Buffer.byteLength(JSON.stringify(doc)) > 800000) {
    doc.newcomers = null;
    doc.coverage.newcomers = { status: 'unavailable', reason: 'size-limit' };
  }
  log.log('Daily overview: ' + JSON.stringify({ today, states: coverage, newcomerGroups: doc.newcomers?.length ?? null }));
  return doc;
}
