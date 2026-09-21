// GA4 응답 모양(dimensionValues/metricValues 문자열)을 그대로 흉내 낸 fixture로 transform을 검증한다.
// 실제 API를 부르지 않으므로 서비스 계정 없이도 돈다.

import test from 'node:test';
import assert from 'node:assert/strict';
import { buildDocs, buildCohort, buildSeries, table, ymd, buildEvents } from '../lib/transform.mjs';
import { streamFilter, withStream, Ga4, DEFAULTS } from '../lib/ga4.mjs';
import { buildMockDocs, addDays } from '../../public/assets/js/mock.js';

const row = (dims, mets) => ({ dimensionValues: dims.map((value) => ({ value })), metricValues: mets.map((value) => ({ value: String(value) })) });
const headers = (names) => names.map((name) => ({ name, type: 'TYPE_INTEGER' }));

const core = {
  metricHeaders: headers(['active1DayUsers', 'active7DayUsers', 'active28DayUsers', 'newUsers', 'sessions', 'userEngagementDuration']),
  rows: [
    row(['20260919'], [10, 22, 40, 3, 25, 3000]),
    row(['20260920'], [12, 24, 41, 2, 30, 4200]),
    row(['20260921'], [14, 27, 44, 5, 36, 5040]),
  ],
  metadata: { currencyCode: 'KRW' },
};
const eventsDaily = {
  rows: [
    row(['20260919', 'first_open'], [3]), row(['20260920', 'first_open'], [2]), row(['20260921', 'first_open'], [5]),
    row(['20260920', 'app_remove'], [1]), row(['20260921', 'app_remove'], [2]),
    row(['20260921', 'ad_impression'], [80]),
    row(['20260921', 'alarm_dismissed'], [40]), row(['20260920', 'alarm_dismissed'], [33]),
    row(['20260921', 'rare_event'], [1]),
  ],
};

test('ymd: GA4의 YYYYMMDD를 ISO 날짜로 바꾼다', () => {
  assert.equal(ymd('20260921'), '2026-09-21');
  assert.equal(ymd('2026-09-21'), '2026-09-21');
});

test('table: rows가 없으면 빈 배열(빈 응답에서 죽지 않는다)', () => {
  assert.deepEqual(table({}), []);
  assert.deepEqual(table(null), []);
});

test('buildSeries: 핵심 지표와 설치/삭제(first_open/app_remove)를 같은 날짜 축에 맞춘다', () => {
  const { series, adsAvailable } = buildSeries({ core, ads: null, eventsDaily });
  assert.deepEqual(series.dates, ['2026-09-19', '2026-09-20', '2026-09-21']);
  assert.deepEqual(series.dau, [10, 12, 14]);
  assert.deepEqual(series.mau, [40, 41, 44]);
  assert.deepEqual(series.installs, [3, 2, 5]);
  assert.deepEqual(series.uninstalls, [0, 1, 2]);
  assert.equal(adsAvailable, true, 'ad_impression 이벤트만 있어도 광고 데이터가 있다고 본다');
  assert.deepEqual(series.adImpressions, [0, 0, 80]);
});

test('buildSeries: 광고 리포트가 있으면 그 값을 쓰고, 전부 0이면 광고 없음', () => {
  const zeroAds = {
    metricHeaders: headers(['publisherAdImpressions', 'publisherAdClicks', 'totalAdRevenue']),
    rows: [row(['20260921'], [0, 0, 0])],
  };
  const noAdEvents = { rows: [row(['20260921', 'first_open'], [1])] };
  assert.equal(buildSeries({ core, ads: zeroAds, eventsDaily: noAdEvents }).adsAvailable, false);

  const ads = {
    metricHeaders: headers(['publisherAdImpressions', 'publisherAdClicks', 'totalAdRevenue']),
    rows: [row(['20260920'], [100, 2, 0.12345678])],
  };
  const r = buildSeries({ core, ads, eventsDaily: noAdEvents });
  assert.equal(r.adsAvailable, true);
  assert.deepEqual(r.series.adImpressions, [0, 100, 0]);
  assert.equal(r.series.adRevenue[1], 0.1235);
});

test('buildEvents: 상위 N개 + 항상 보관(first_open 등)만 남기고 합계를 계산', () => {
  const dates = ['2026-09-19', '2026-09-20', '2026-09-21'];
  const ev = buildEvents({ eventsDaily, dates, keep: 2 });
  assert.ok(ev.series.alarm_dismissed, '상위 2개(ad_impression 80, alarm_dismissed 73)는 남는다');
  assert.ok(ev.series.first_open && ev.series.app_remove && ev.series.ad_impression, '항상 보관 목록');
  assert.equal(ev.series.rare_event, undefined, '드문 이벤트는 잘린다');
  assert.equal(ev.totals.alarm_dismissed, 73);
});

test('buildCohort: N일차 잔존율 = N일차 활성 / 0일차', () => {
  const resp = {
    rows: [row(['c', '0000'], [100]), row(['c', '0001'], [40]), row(['c', '0002'], [25]), row(['c', '0007'], [12])],
  };
  const c = buildCohort(resp, { from: '2026-08-01', to: '2026-08-31' });
  assert.equal(c.size, 100);
  assert.equal(c.days[0], 1);
  assert.equal(c.days[1], 0.4);
  assert.equal(c.days[7], 0.12);
  assert.equal(c.days.length, 8);
  assert.equal(buildCohort({ rows: [] }, { from: 'a', to: 'b' }), null);
  assert.equal(buildCohort({ rows: [row(['c', '0000'], [0])] }, { from: 'a', to: 'b' }), null);
});

test('buildDocs: summary KPI는 마지막 날 기준이고 사용자 정의 이벤트 여부를 플래그로 낸다', () => {
  const docs = buildDocs({
    raw: { core, ads: null, eventsDaily, eventsSummary: { rows: [row(['first_open'], [10, 8]), row(['alarm_dismissed'], [73, 6])] } },
    meta: { now: new Date('2026-09-22T03:00:00Z'), propertyId: '553838010', streamId: '15763725797', cohortRange: { from: 'a', to: 'b' } },
  });
  assert.equal(docs.summary.latest, '2026-09-21');
  assert.equal(docs.summary.kpi.dau, 14);
  assert.equal(docs.summary.kpi.mau, 44);
  assert.equal(docs.summary.kpi.stickiness, 0.3182);
  assert.equal(docs.summary.kpi.installs, 5);
  assert.equal(docs.summary.flags.customEvents, true);
  assert.equal(docs.summary.streamId, '15763725797');
  assert.deepEqual(docs.summary.events[0], { name: 'first_open', count: 10, users: 8 });
  assert.equal(docs.summary.cohort, null);
});

test('출시 앱만 집계: 모든 리포트에 streamId 필터가 걸린다(dev·웹 스트림 제외)', () => {
  const ga = new Ga4({ auth: null, propertyId: DEFAULTS.propertyId, streamId: DEFAULTS.streamId });
  const reports = [ga.coreDaily(30), ga.adsDaily(30), ga.eventsDaily(30), ga.eventsSummary(), ga.breakdown('appVersion'),
    ga.cohort({ from: '2026-08-01', to: '2026-08-15' })];
  for (const r of reports) {
    assert.deepEqual(r.dimensionFilter, streamFilter('15763725797'));
  }
  assert.equal(DEFAULTS.streamId, '15763725797');
  assert.notEqual(DEFAULTS.streamId, '15763791924', 'dev 스트림이면 안 된다');
  const combined = withStream('15763725797', { filter: { fieldName: 'eventName', stringFilter: { value: 'x' } } });
  assert.equal(combined.andGroup.expressions.length, 2);
});

test('모의 데이터도 같은 스키마·불변식을 지킨다(mau>=wau>=dau, 배열 길이 일치)', () => {
  const { summary, series, events } = buildMockDocs();
  const n = series.dates.length;
  for (const key of ['dau', 'wau', 'mau', 'newUsers', 'sessions', 'engagementSec', 'installs', 'uninstalls', 'adImpressions', 'adClicks', 'adRevenue']) {
    assert.equal(series[key].length, n, key);
  }
  for (let i = 0; i < n; i += 1) {
    assert.ok(series.mau[i] >= series.wau[i] && series.wau[i] >= series.dau[i], `i=${i}`);
  }
  assert.equal(summary.latest, series.dates[n - 1]);
  assert.equal(summary.latest, addDays('2026-09-22', -1));
  for (const arr of Object.values(events.series)) assert.equal(arr.length, n);
  assert.equal(buildMockDocs().summary.kpi.dau, summary.kpi.dau, '결정적(seed 고정)');
});
