import { EVENT_META } from './labels.js';

export const FEATURE_NAMES = Object.entries(EVENT_META).filter(([name, meta]) =>
  !meta.retired && meta.group !== 'system' && name !== 'onboarding_complete' && name !== 'auto_backup_created' &&
  !name.startsWith('ops_') && !name.startsWith('alarm_schedule_') && !name.startsWith('alarm_refresh_') &&
  !['alarm_fired', 'device_boot_seen', 'alarm_no_response'].includes(name)).map(([name]) => name);
export const dayShift = (date, n) => new Date(Date.parse(date + 'T00:00:00Z') + n * 86400000).toISOString().slice(0,10);
export const constrained = s => s?.thresholded || s?.sampled || s?.truncated || s?.otherRowLoss;
export function comparisonRows(docs, mode = 'live') {
  const pulse = docs.pulse;
  const today = pulse?.today;
  if (!today) return { dates: [], rows: [] };
  const last = mode === 'closed' ? dayShift(today, -1) : today;
  const dates = [dayShift(last, -1), last];
  const available = pulse.events != null && pulse.coverage?.events?.status !== 'unavailable';
  const seen = new Set(pulse.events?.map(r => r.name));
  const rows = FEATURE_NAMES.map(name => {
    const values = dates.map(date => {
      const r = pulse.events?.find(r => r.date === date && r.name === name);
      return r ? r.count : available && !constrained(pulse.coverage?.events) && seen.has(name) ? 0 : null;
    });
    return { name, label: EVENT_META[name].label, values, score: (values[0] ?? 0) + (values[1] ?? 0), observed: seen.has(name) };
  }).sort((a,b) => b.score - a.score || Number(b.observed) - Number(a.observed) || a.label.localeCompare(b.label,'ko'));
  return { dates, rows, available, limited: constrained(pulse.coverage?.events) };
}
