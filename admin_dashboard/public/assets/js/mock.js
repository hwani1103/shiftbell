// admin_dashboard/public/assets/js/mock.js
//
// 모의 데이터 생성기 - 실제 GA4 없이도 화면을 그대로 확인하고 테스트하기 위한 것.
//  - 브라우저: localhost에서 ?demo 로 열 때만 쓴다(store.js). 운영 주소에서는 절대 쓰지 않는다.
//  - Node: sync.mjs --mock 이 Firestore 에뮬레이터에 같은 문서를 채울 때 쓴다.
// 결정적(seed 고정)이라 스크린샷·테스트가 매번 같은 결과를 낸다. 스키마는 sync/lib/transform.mjs와 동일(schema: 1).

const SCHEMA = 1;

function mulberry32(a) {
  return function rnd() {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const pad = (n) => String(n).padStart(2, '0');
export function addDays(ymd, delta) {
  const [y, m, d] = ymd.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + delta));
  return `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`;
}
export function weekdayOf(ymd) {
  const [y, m, d] = ymd.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay(); // 0=일
}

/** 사용자 정의 이벤트: 활성 사용자 1명당 하루 평균 발생 횟수(모의용). 이름은 앱 코드(AppAnalytics)와 같아야 한다. */
const CUSTOM_RATES = {
  alarm_dismissed: 1.05,
  alarm_snoozed: 0.22,
  alarm_no_response: 0.04,
  tab_selected: 3.6,
  memo_saved: 0.16,
  shift_assigned: 0.14,
  schedule_created: 0.11,
  sleep_record_saved: 0.09,
  alarm_template_saved: 0.05,
  ot_saved: 0.045,
  calendar_theme_changed: 0.03,
  help_opened: 0.02,
  backup_created: 0.018,
  friend_added: 0.012,
  friend_share_started: 0.008,
  backup_restored: 0.004,
};

/**
 * @param {{today?: string, days?: number, seed?: number}} opts
 *   today: '오늘' 날짜(YYYY-MM-DD). 마지막 데이터는 그 전날(어제)까지.
 */
export function buildMockDocs({ today = '2026-09-22', days = 400, seed = 20260922 } = {}) {
  const rnd = mulberry32(seed);
  const latest = addDays(today, -1);
  const dates = [];
  for (let i = days - 1; i >= 0; i -= 1) dates.push(addDays(latest, -i));
  const n = dates.length;

  // 출시(업데이트) 날짜 - 설치가 튀는 날
  const bumps = new Map([[n - 9, 34], [n - 41, 26], [n - 96, 18], [n - 178, 22], [n - 260, 15]]);

  const installs = new Array(n).fill(0);
  const dauBase = new Array(n).fill(0);
  for (let i = 0; i < n; i += 1) {
    const growth = 0.6 + (i / n) * 3.2; // 서서히 성장
    const wd = weekdayOf(dates[i]);
    const weekly = wd === 0 || wd === 6 ? 0.86 : 1.06;
    let inst = growth * weekly * (0.7 + rnd() * 0.8);
    for (const [bi, boost] of bumps) if (i >= bi && i < bi + 6) inst += boost * Math.exp(-(i - bi) * 0.6);
    installs[i] = Math.max(0, Math.round(inst));
  }
  // 누적 설치 기반 활성(설치 잔존 모델)
  let alive = 6;
  for (let i = 0; i < n; i += 1) {
    alive = alive * 0.985 + installs[i] * 0.82;
    const wd = weekdayOf(dates[i]);
    const weekly = wd === 0 ? 0.9 : wd === 6 ? 0.94 : 1.04;
    dauBase[i] = alive * 0.36 * weekly * (0.93 + rnd() * 0.14);
  }

  const dau = dauBase.map((v) => Math.round(v));
  const avg = (arr, i, w) => { let s = 0; let c = 0; for (let k = Math.max(0, i - w + 1); k <= i; k += 1) { s += arr[k]; c += 1; } return s / c; };
  const wau = dau.map((_, i) => Math.max(dau[i], Math.round(avg(dau, i, 7) * 1.85)));
  const mau = dau.map((_, i) => Math.max(wau[i], Math.round(avg(dau, i, 28) * 2.75)));
  const newUsers = installs.map((v) => Math.round(v * 0.93));
  const sessions = dau.map((v) => Math.round(v * (2.5 + rnd() * 0.9)));
  const engagementSec = dau.map((v) => Math.round(v * (190 + rnd() * 140)));
  const uninstalls = installs.map((_, i) => {
    const lag = i >= 3 ? installs[i - 3] : installs[i];
    return Math.max(0, Math.round(lag * (0.18 + rnd() * 0.16)));
  });
  const adImpressions = sessions.map((v) => Math.round(v * (2.0 + rnd() * 0.6)));
  const adClicks = adImpressions.map((v) => Math.round(v * (0.008 + rnd() * 0.008)));
  const adRevenue = adImpressions.map((v) => Math.round(v * (0.0005 + rnd() * 0.0004) * 10000) / 10000);

  const series = {
    schema: SCHEMA, dates, dau, wau, mau, newUsers, sessions, engagementSec,
    installs, uninstalls, adImpressions, adClicks, adRevenue,
  };

  const evSeries = {
    first_open: installs, app_remove: uninstalls, session_start: sessions,
    screen_view: sessions.map((v) => Math.round(v * 5.4)),
    user_engagement: sessions.map((v) => Math.round(v * 3.1)),
    ad_impression: adImpressions,
  };
  // 사용자 정의 이벤트는 앱에 계측을 넣은 시점부터 쌓이므로 최근 60일만 값이 있다(실제 상황을 흉내).
  const customStart = n - 60;
  for (const [name, rate] of Object.entries(CUSTOM_RATES)) {
    evSeries[name] = dau.map((v, i) => (i < customStart ? 0 : Math.round(v * rate * (0.8 + rnd() * 0.4))));
  }
  evSeries.onboarding_complete = installs.map((v, i) => (i < customStart ? 0 : Math.round(v * 0.86)));

  const totals = {};
  for (const [name, arr] of Object.entries(evSeries)) totals[name] = arr.reduce((a, b) => a + b, 0);
  const events = { schema: SCHEMA, dates, series: evSeries, totals };

  const sum = (arr, from = n - 30) => arr.slice(from).reduce((a, b) => a + b, 0);
  const users30 = (name) => Math.min(mau[n - 1], Math.round(sum(evSeries[name]) / (name === 'tab_selected' ? 9 : name === 'alarm_dismissed' ? 14 : 3) + 1));
  const eventSummary = Object.keys(evSeries)
    .map((name) => ({ name, count: sum(evSeries[name]), users: users30(name) }))
    .filter((e) => e.count > 0)
    .sort((a, b) => b.count - a.count);

  const pct = (list, total) => list.map(([name, share]) => ({ name, users: Math.round(total * share) }));
  const total = mau[n - 1];
  const summary = {
    schema: SCHEMA,
    updatedAt: `${today}T03:10:00.000Z`,
    propertyId: '553838010',
    streamId: '15763725797',
    source: 'mock',
    currency: 'USD',
    range: { start: dates[0], end: dates[n - 1] },
    latest: dates[n - 1],
    kpi: {
      dau: dau[n - 1], wau: wau[n - 1], mau: mau[n - 1],
      stickiness: Math.round((dau[n - 1] / mau[n - 1]) * 10000) / 10000,
      newUsers: newUsers[n - 1], installs: installs[n - 1], uninstalls: uninstalls[n - 1],
      sessions: sessions[n - 1],
      sessionsPerUser: Math.round((sessions[n - 1] / dau[n - 1]) * 100) / 100,
      engagementSecPerUser: Math.round(engagementSec[n - 1] / dau[n - 1]),
    },
    cohort: {
      size: 137,
      days: [1, 0.43, 0.36, 0.32, 0.29, 0.27, 0.26, 0.25, 0.23, 0.22, 0.21, 0.2, 0.2, 0.19, 0.18],
      from: addDays(latest, -45), to: addDays(latest, -15),
    },
    breakdowns: {
      appVersion: pct([['1.0.23', 0.42], ['1.0.22', 0.36], ['1.0.21', 0.14], ['1.0.20', 0.05], ['1.0.19', 0.03]], total),
      os: pct([['14', 0.34], ['15', 0.27], ['13', 0.22], ['12', 0.11], ['11', 0.06]], total),
      language: pct([['한국어', 0.951], ['영어', 0.034], ['일본어', 0.008], ['기타', 0.007]], total),
      country: pct([['대한민국', 0.962], ['미국', 0.014], ['일본', 0.01], ['캐나다', 0.005], ['호주', 0.004]], total),
      device: pct([['SM-S928N', 0.18], ['SM-S918N', 0.15], ['SM-S938N', 0.12], ['SM-A546S', 0.09], ['SM-F946N', 0.06], ['Pixel 8', 0.03]], total),
    },
    events: eventSummary,
    flags: { ads: true, customEvents: true },
  };
  return { summary, series, events };
}
