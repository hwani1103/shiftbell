import { dimensionLabel, eventName } from './report-values.mjs';
const table = (report) => (report?.rows ?? []).map((row) => ({ d: (row.dimensionValues ?? []).map((d) => d.value), m: (row.metricValues ?? []).map((m) => Number(m.value) || 0) }));
const ymd = (s) => String(s).length === 8 ? String(s).slice(0, 4) + '-' + String(s).slice(4, 6) + '-' + String(s).slice(6, 8) : String(s);

const metrics = (report) => Object.fromEntries((report?.metricHeaders ?? []).map((h, i) => [h.name, i]));
export function reportState(report) {
  if (report == null) return { status: 'unavailable' };
  return {
    status: table(report).length ? 'available' : 'empty',
    thresholded: report.metadata?.subjectToThresholding === true,
    otherRowLoss: report.metadata?.dataLossFromOtherRow === true,
    sampled: (report.metadata?.samplingMetadatas?.length ?? 0) > 0,
    truncated: Number(report.rowCount ?? 0) > (report.rows?.length ?? 0),
  };
}
export function periodStats(report) {
  if (!report) return null;
  const idx = metrics(report); const row = table(report)[0];
  const get = (name) => row?.m[idx[name]] ?? 0;
  return { activeUsers: get('activeUsers'), totalUsers: get('totalUsers'), newUsers: get('newUsers'),
    sessions: get('sessions'), engagementSec: get('userEngagementDuration') };
}
export function segmentStats(report, eventReport, dimensionCount = 1) {
  if (!report) return null;
  const idx = metrics(report);
  const grouped = new Map();
  for (const row of table(eventReport)) {
    const name = dimensionCount === 1 ? dimensionLabel(row.d[0]) : JSON.stringify(row.d.slice(0, dimensionCount).map(dimensionLabel));
    const event = eventName(row.d[dimensionCount]);
    if (event == null) continue;
    if (!grouped.has(name)) grouped.set(name, {});
    grouped.get(name)[event] = { count: row.m[0], users: row.m[1] ?? null };
  }
  return table(report).map((row) => {
    const name = dimensionCount === 1 ? dimensionLabel(row.d[0]) : JSON.stringify(row.d.slice(0, dimensionCount).map(dimensionLabel));
    const get = (metric) => row.m[idx[metric]] ?? 0;
    return { name, ...(dimensionCount === 2 ? {country: dimensionLabel(row.d[0]), language: dimensionLabel(row.d[1])} : {}), activeUsers: get('activeUsers'), totalUsers: get('totalUsers'), newUsers: get('newUsers'),
      sessions: get('sessions'), engagementSec: get('userEngagementDuration'),
      events: eventReport == null ? null : (grouped.get(name) ?? {}) };
  });
}
export function countryTrend(report, maxCountries = 50, dimensionCount = 1) {
  if (!report) return null;
  const rows = table(report); const totals = new Map();
  const key = row => dimensionCount === 1 ? dimensionLabel(row.d[1]) : JSON.stringify(row.d.slice(1, dimensionCount + 1).map(dimensionLabel));
  for (const row of rows) totals.set(key(row), (totals.get(key(row)) ?? 0) + row.m[0]);
  const names = [...totals].sort((a, b) => b[1] - a[1]).slice(0, maxCountries).map(([name]) => name);
  const dates = [...new Set(rows.map((row) => ymd(row.d[0])))].sort();
  const pos = new Map(dates.map((date, i) => [date, i]));
  const series = Object.fromEntries(names.map((name) => [name, { dau: dates.map(() => 0), newUsers: dates.map(() => 0), sessions: dates.map(() => 0) }]));
  for (const row of rows) {
    const item = series[key(row)]; if (!item) continue;
    const i = pos.get(ymd(row.d[0]));
    item.dau[i] += row.m[0]; item.newUsers[i] += row.m[1]; item.sessions[i] += row.m[2];
  }
  return { dates, series, retainedCountries: names.length, availableCountries: totals.size };
}
export function buildOperations(raw, meta) {
  const byRange = {};
  for (const [range, data] of Object.entries(raw.operationsByRange ?? {})) {
    byRange[range] = { from: data.from, to: data.to,
      current: periodStats(data.current), previous: periodStats(data.previous),
      countries: segmentStats(data.countries, data.countryEvents),
      previousCountries: segmentStats(data.previousCountries, null),
      countryLanguages: segmentStats(data.countryLanguages, data.countryLanguageEvents, 2),
      previousCountryLanguages: segmentStats(data.previousCountryLanguages, null, 2),
      manufacturers: segmentStats(data.manufacturers, data.manufacturerEvents),
      coverage: Object.fromEntries(['current', 'previous', 'countries', 'countryEvents', 'previousCountries', 'countryLanguages', 'previousCountryLanguages', 'countryLanguageEvents', 'manufacturers', 'manufacturerEvents']
        .map((name) => [name, reportState(data[name])])),
    };
  }
  return { schema: 4, updatedAt: meta.now.toISOString(), byRange, countryTrend: countryTrend(raw.countryDaily), countryLanguageTrend: countryTrend(raw.countryLanguageDaily, 100, 2),
    coverage: { countryDaily: reportState(raw.countryDaily), countryLanguageDaily: reportState(raw.countryLanguageDaily) } };
}
