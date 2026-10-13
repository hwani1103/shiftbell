// Eight scheduled refreshes per day. Slots tolerate scheduler delays without a
// daily guard suppressing later corrections from GA4.
const INTERVAL_MS = 3 * 60 * 60 * 1000;
const OFFSET_MS = 17 * 60 * 1000;
export function syncPolicy(now = new Date()) {
  return { frequency: 'every-3-hours', timezone: 'Asia/Seoul', intervalHours: 3, schedulerCheckMinutes: 60,
    scheduledAt: ['00:17', '03:17', '06:17', '09:17', '12:17', '15:17', '18:17', '21:17'],
    day: new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(now),
    slot: new Date(Math.floor((now.getTime() - OFFSET_MS) / INTERVAL_MS) * INTERVAL_MS + OFFSET_MS).toISOString(),
    endDate: 'yesterday' };
}
export function alreadySyncedInSlot(previous, now = new Date()) {
  return previous?.pipelineVersion === 2 &&
    previous?.syncPolicy?.frequency === 'every-3-hours' &&
    previous.syncPolicy.slot === syncPolicy(now).slot;
}
