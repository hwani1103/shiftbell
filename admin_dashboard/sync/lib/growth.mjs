import { streamFilter, withStream } from './ga4.mjs';
import { reportState } from './operations.mjs';

export const shiftDate = (date, days) => new Date(Date.parse(date + 'T00:00:00Z') + days * 86400000).toISOString().slice(0, 10);
const exact = (name, value) => ({ filter: { fieldName: name, stringFilter: { matchType: 'EXACT', value } } });
export const TRAFFIC_SCOPES = ['all', 'ads', 'organic'];
export function trafficFilter(scope) {
  if (scope === 'ads') return exact('firstUserSourcePlatform', 'Google Ads');
  if (scope === 'organic') return { andGroup: { expressions: [exact('firstUserDefaultChannelGroup', 'Organic Search'), { notExpression: exact('firstUserSourcePlatform', 'Google Ads') }] } };
  return null;
}
export function reportRows(report) {
  const dimensions = report?.dimensionHeaders?.map(h => h.name) ?? [];
  const metrics = report?.metricHeaders?.map(h => h.name) ?? [];
  return (report?.rows ?? []).map(r => Object.fromEntries([
    ...dimensions.map((name, i) => [name, r.dimensionValues?.[i]?.value ?? '']),
    ...metrics.flatMap((name, i) => i < (r.metricValues?.length ?? 0) && metrics.indexOf(name) === i ? [[name, Number(r.metricValues[i].value) || 0]] : []),
  ]));
}
export function acquisitionQuery(streamId, from, to, mode = 'channels') {
  const dimensions = mode === 'campaigns' ? ['firstUserCampaignName', 'firstUserSourcePlatform']
    : mode === 'countries' ? ['country', 'firstUserDefaultChannelGroup', 'firstUserSourcePlatform']
    : mode === 'daily' ? ['date', 'firstUserDefaultChannelGroup', 'firstUserSourcePlatform']
    : ['firstUserDefaultChannelGroup', 'firstUserSourcePlatform'];
  return { dateRanges: [{ startDate: from, endDate: to }], dimensions: dimensions.map(name => ({ name })),
    metrics: [{ name: 'newUsers' }], dimensionFilter: streamFilter(streamId), limit: '10000' };
}
// The first step excludes the final observation day, leaving a full 24 hours for completion.
// A closed event funnel guarantees the numerator belongs to the same first-open users.
export function activationQuery(streamId, from, to, scope = 'all', countryBreakdown = false) {
  const firstTo = shiftDate(to, -1);
  return {
    dateRanges: [{ startDate: from, endDate: to }],
    dimensionFilter: withStream(streamId, trafficFilter(scope)),
    funnel: { isOpenFunnel: false, steps: [
      { name: 'First open', filterExpression: { andGroup: { expressions: [
        { funnelEventFilter: { eventName: 'first_open' } },
        { funnelFieldFilter: { fieldName: 'date', betweenFilter: { fromValue: { int64Value: from.replaceAll('-', '') }, toValue: { int64Value: firstTo.replaceAll('-', '') } } } },
      ] } } },
      { name: 'Schedule ready', withinDurationFromPriorStep: '86400s', filterExpression: { funnelEventFilter: { eventName: 'onboarding_complete' } } },
    ] },
    ...(countryBreakdown ? { funnelBreakdown: { breakdownDimension: { name: 'country' }, limit: '15' } } : {}),
    limit: '1000',
  };
}
export function retentionQuery(streamId, latest, day, scope = 'all', byCountry = false) {
  const to = shiftDate(latest, -day); const from = shiftDate(to, -6);
  return { dimensions: ['cohort', 'cohortNthDay', ...(byCountry ? ['country'] : [])].map(name => ({ name })),
    metrics: [{ name: 'cohortActiveUsers' }, { name: 'cohortTotalUsers' }],
    cohortSpec: { cohorts: [{ name: 'recent', dimension: 'firstSessionDate', dateRange: { startDate: from, endDate: to } }],
      cohortsRange: { granularity: 'DAILY', startOffset: day, endOffset: day } },
    dimensionFilter: withStream(streamId, trafficFilter(scope)), limit: '1000' };
}
export function trafficKey(row) {
  if (row.firstUserSourcePlatform === 'Google Ads') return 'ads';
  if (row.firstUserDefaultChannelGroup === 'Organic Search') return 'organic';
  const channel = row.firstUserDefaultChannelGroup || '';
  if (/Paid|Cross-network|Display|Audio/i.test(channel)) return 'otherPaid';
  if (!channel || ['Direct', 'Unassigned', '(not set)', '(other)'].includes(channel)) return 'unknown';
  return 'other';
}
export function channelTotals(report) {
  if (report == null) return null;
  const totals = { ads: 0, organic: 0, otherPaid: 0, unknown: 0, other: 0 };
  for (const r of reportRows(report)) totals[trafficKey(r)] += r.newUsers;
  return totals;
}
export function parseFunnel(report, from, to) {
  const table = report?.funnelTable;
  if (!table) return { status: 'unavailable', from, to: shiftDate(to, -1), entrants: null, completed: null, rate: null };
  const rows = reportRows(table).filter(r => !r.country || ['RESERVED_TOTAL', '(not set)'].includes(r.country));
  const first = rows.find(r => /^1[. ]/.test(r.funnelStepName));
  const second = rows.find(r => /^2[. ]/.test(r.funnelStepName));
  const entrants = first?.activeUsers ?? 0; const completed = second?.activeUsers ?? 0;
  const limited = table.metadata?.subjectToThresholding || table.metadata?.samplingMetadatas?.length > 0;
  return { status: limited ? 'limited' : entrants ? 'available' : 'empty', from, to: shiftDate(to, -1), entrants, completed,
    rate: entrants > 0 && completed <= entrants && !limited ? completed / entrants : null };
}
export function parseRetention(report, latest, day) {
  const to = shiftDate(latest, -day); const from = shiftDate(to, -6);
  const row = reportRows(report)[0];
  const state = reportState(report);
  const size = report == null ? null : row?.cohortTotalUsers ?? 0;
  const returned = report == null ? null : row?.cohortActiveUsers ?? 0;
  const limited = state.thresholded || state.sampled || state.truncated || state.otherRowLoss;
  return { ...state, from, to, day, size, returned,
    rate: size > 0 && returned <= size && !limited ? returned / size : null };
}
async function optional(label, fn, log) {
  try { return await fn(); } catch (error) { log.warn('Growth ' + label + ': ' + String(error.message).slice(0, 450)); return null; }
}
export async function fetchGrowth(ga, latest, now, log = console) {
  const result = { schema: 1, updatedAt: now.toISOString(), latest, byRange: {}, retention: {}, coverage: {} };
  for (const range of [7, 30, 100, 365]) {
    const from = shiftDate(latest, 1 - range);
    const reports = {};
    for (const mode of ['channels', 'countries', 'campaigns']) reports[mode] = await optional(mode, () => ga.runReport(acquisitionQuery(ga.streamId, from, latest, mode)), log);
    const funnels = {};
    for (const scope of TRAFFIC_SCOPES) {
      const raw = await optional('activation/' + scope, () => ga.runFunnelReport(activationQuery(ga.streamId, from, latest, scope)), log);
      funnels[scope] = parseFunnel(raw, from, latest);
    }
    result.byRange[range] = { from, to: latest, channels: channelTotals(reports.channels),
      countries: reports.countries == null ? null : reportRows(reports.countries),
      campaigns: reports.campaigns == null ? null : reportRows(reports.campaigns).filter(r => r.firstUserSourcePlatform === 'Google Ads'),
      activation: funnels, coverage: Object.fromEntries(Object.entries(reports).map(([key, raw]) => [key, reportState(raw)])) };
    log.log('Growth ' + range + 'd: ' + JSON.stringify({ channels: result.byRange[range].channels, activation: Object.fromEntries(Object.entries(funnels).map(([s, f]) => [s, {status:f.status, entrants:f.entrants, completed:f.completed}])) }));
  }
  for (const scope of TRAFFIC_SCOPES) {
    result.retention[scope] = {};
    for (const day of [1, 7]) {
      const raw = await optional('retention/' + scope + '/' + day, () => ga.runReport(retentionQuery(ga.streamId, latest, day, scope)), log);
      result.retention[scope][day] = parseRetention(raw, latest, day);
    }
  }
  const trend = await optional('daily', () => ga.runReport(acquisitionQuery(ga.streamId, shiftDate(latest, -99), latest, 'daily')), log);
  result.daily = trend == null ? null : reportRows(trend);
  result.coverage.daily = reportState(trend);
  return result;
}
