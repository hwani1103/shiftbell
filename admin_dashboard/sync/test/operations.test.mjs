import test from 'node:test';
import assert from 'node:assert/strict';
import { Ga4, DEFAULTS } from '../lib/ga4.mjs';
import { reportState, periodStats, segmentStats, countryTrend } from '../lib/operations.mjs';
import { buildMockDocs } from '../../public/assets/js/mock.js';
import { computeView } from '../../public/assets/js/views.js';
import { periodData, eventData, adoptionCard, revenueCard, reliabilityCard } from '../../public/assets/js/operations.js';
const report = (metrics, rows, metadata = {}) => ({metricHeaders: metrics.map(name => ({name})), rows: rows.map(([dims, vals]) => ({dimensionValues: dims.map(value => ({value})), metricValues: vals.map(value => ({value: String(value)}))})), metadata});
test('all business queries use production stream and completed dates', () => {
  const ga = new Ga4({auth: null});
  for (const query of [ga.periodSummary('2026-10-01','2026-10-10'),ga.segmentSummary('country','2026-10-01','2026-10-10'),ga.segmentEvents('mobileDeviceBranding','2026-10-01','2026-10-10'),ga.countryDaily()]) {
    assert.match(JSON.stringify(query.dimensionFilter), new RegExp(DEFAULTS.streamId));
    assert.equal(query.dateRanges[0].endDate === 'today', false);
  }
  assert.deepEqual(ga.periodSummary('a','b').metrics.map(m => m.name), ['activeUsers','totalUsers','newUsers','sessions','userEngagementDuration']);
});
test('unavailable differs from empty and limited reports', () => {
  assert.equal(reportState(null).status,'unavailable');
  assert.equal(periodStats(null),null);
  assert.equal(reportState({rows:[]}).status,'empty');
  assert.equal(periodStats({rows:[]}).activeUsers,0);
  const r = report(['activeUsers'], [[['Korea'],[3]]], {subjectToThresholding:true}); r.rowCount=5;
  assert.equal(reportState(r).thresholded,true); assert.equal(reportState(r).truncated,true);
  assert.equal(segmentStats(r,null)[0].events,null);
});
test('country metrics keep period distinct users and unavailable event counts', () => {
  const r=report(['activeUsers','totalUsers','newUsers','sessions','userEngagementDuration'],[[['Korea'],[8,10,2,20,600]]]);
  const e=report(['eventCount','totalUsers'],[[['Korea','alarm_fired'],[9,3]]]);
  assert.deepEqual(segmentStats(r,e)[0],{name:'Korea',activeUsers:8,totalUsers:10,newUsers:2,sessions:20,engagementSec:600,events:{alarm_fired:{count:9,users:3}}});
  const daily=report(['activeUsers','newUsers','sessions'],[[['20261001','Korea'],[3,1,4]],[['20261002','Korea'],[4,0,5]]]);
  assert.deepEqual(countryTrend(daily).series.Korea.dau,[3,4]);
});
test('event users and denominators require exactly matching periods', () => {
  const docs=buildMockDocs(); const view=computeView(docs,30);
  assert.ok(periodData(docs,view));
  assert.notEqual(eventData(docs,view,'memo_saved').users,null);
  const mismatch={...view,dates:['2020-01-01',...view.dates.slice(1)]};
  assert.equal(periodData(docs,mismatch),null);
  assert.equal(eventData(docs,mismatch,'memo_saved').users,null);
  const d=structuredClone(docs); d.operations.byRange[30].current.totalUsers=1;
  d.summary.eventsByRange[30].events.find(e=>e.name==='memo_saved').users=100;
  assert.equal(adoptionCard(d,view).includes('10000.0%'),false);
});
test('unknown revenue and unobserved alarm telemetry do not assert success', () => {
  const docs=buildMockDocs(); const view=computeView(docs,30);
  docs.summary.coverage.ads={status:'unavailable'};
  assert.match(revenueCard(docs,view),/—/);
  for(const key of Object.keys(docs.events.series)) if(key.startsWith('alarm_schedule')) delete docs.events.series[key];
  docs.summary.eventsByRange[30].events=docs.summary.eventsByRange[30].events.filter(e=>!e.name.startsWith('alarm_schedule'));
  assert.match(reliabilityCard(docs,view),/미관측/);
  assert.match(reliabilityCard(docs,view),/울림 성공률로 계산하지 않습니다/);
});

test('unobserved feature does not imply a zero adoption rate', () => {const docs=buildMockDocs();const view=computeView(docs,30);delete docs.events.series.team_roster_created;docs.summary.eventsByRange[30].events=docs.summary.eventsByRange[30].events.filter(e=>e.name!=='team_roster_created');const row=adoptionCard(docs,view).match(/<tr[^>]*data-event="team_roster_created"[\s\S]*?<\/tr>/)[0];assert.match(row,/미관측/);assert.equal(row.includes('adoption'),false);assert.match(row,/>—<\/td>/);});
