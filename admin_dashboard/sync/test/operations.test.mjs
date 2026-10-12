import test from 'node:test';
import assert from 'node:assert/strict';
import { Ga4, DEFAULTS } from '../lib/ga4.mjs';
import { reportState, periodStats, segmentStats, countryTrend } from '../lib/operations.mjs';
import { buildMockDocs } from '../../public/assets/js/mock.js';
import { computeView } from '../../public/assets/js/views.js';
import { periodData, eventData, adoptionCard, revenueCard, reliabilityCard, dailyView, dailyOverviewCard, dailySelection, weekdayDauAverages, countryCard, groupedCountryRows } from '../../public/assets/js/operations.js';
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

test('overview DAU follows selected periods while MAU keeps its 28-day value', () => {
  const docs=buildMockDocs();
  const expectedMau=docs.series.mau.at(-1).toLocaleString('en-US')+'명';
  for(const range of [7,30,100,365]) {
    const recent=dailyView(docs,'2026-09-21',range);
    assert.equal(recent.dates.length,range);
    assert.equal(recent.dates.at(-1),'2026-09-21');
    assert.equal(recent.yesterdayValue('dau'),docs.series.dau.at(-1));
    const html=dailyOverviewCard(docs,recent,{range,visible:{dau:true,mau:true}});
    assert.ok(html.includes('최근 '+range+'일 DAU 추이'));
    assert.equal(recent.yesterdayValue('mau'),docs.series.mau.at(-1));
    assert.ok(html.includes(expectedMau));
    assert.equal((html.match(/data-action="daily-day"/g)??[]).length,0);
  }
});
test('missing yesterday remains pending instead of relabeling old DAU', () => {const docs=buildMockDocs();const recent=dailyView(docs,'2026-09-22');assert.equal(recent.yesterdayValue('dau'),null);assert.equal(recent.yesterdayValue('mau'),null);assert.equal(recent.dates.length,29);assert.match(dailyOverviewCard(docs,recent,{visible:{dau:true,mau:true}}),/어제 자료는 아직 집계되지/);});
test('feature adoption is sorted by period usage with unknowns last', () => {const docs=buildMockDocs();const view=computeView(docs,30);delete docs.events.series.team_roster_created;docs.summary.eventsByRange[30].events=docs.summary.eventsByRange[30].events.filter(e=>e.name!=='team_roster_created');const names=[...adoptionCard(docs,view).matchAll(/data-event="([a-z_]+)"/g)].map(m=>m[1]);const unknownIndex=names.indexOf('team_roster_created');assert.ok(unknownIndex>=0);assert.ok(names.slice(unknownIndex).every(name=>!eventData(docs,view,name).observed));const counts=names.map(name=>eventData(docs,view,name).count);assert.deepEqual(counts,[...counts].sort((a,b)=>b-a));});

test('schedule summary counts appear in usage ranking without a percentage column', () => {const docs=buildMockDocs();const view=computeView(docs,30);delete docs.events.series.schedule_created;docs.summary.eventsByRange[30].events=docs.summary.eventsByRange[30].events.filter(e=>e.name!=='schedule_created');docs.summary.eventsByRange[30].events.push({name:'schedule_created',count:999999,users:17});assert.equal(eventData(docs,view,'schedule_created').count,999999);const html=adoptionCard(docs,view);assert.equal([...html.matchAll(/data-event="([a-z_]+)"/g)][0][1],'schedule_created');assert.match(html,/일정 생성/);assert.match(html,/17명/);assert.equal(html.includes('기간 이용자 대비'),false);assert.equal((html.match(/<thead>[\s\S]*?<\/thead>/)[0].match(/<th>/g)||[]).length,3);});
test('DAU headline follows selection and missing yesterday remains unknown', () => {const docs=buildMockDocs();const recent=dailyView(docs,'2026-09-21');const selected=dailySelection(recent,recent.dates[0]);assert.equal(selected.label,'선택일 DAU');assert.equal(selected.value,recent.cur('dau')[0].toLocaleString('en-US')+'명');assert.equal(dailySelection(recent,recent.yesterday).label,'어제 DAU');const pending=dailyView(docs,'2026-09-22');assert.equal(dailySelection(pending,pending.yesterday).value,'—');const html=dailyOverviewCard(docs,pending,{visible:{dau:true,mau:false}});assert.match(html,/id="daily-dau-value">—/);assert.equal(html.includes('daily-days'),false);assert.ok(html.indexOf('id="ch-users"')<html.indexOf('weekday-dau'));});

test('feature ranking covers every current user action from shared metadata', async () => {const {EVENT_META}=await import('../../public/assets/js/labels.js');const docs=buildMockDocs();const view=computeView(docs,30);const html=adoptionCard(docs,view);const names=[...html.matchAll(/data-event="([a-z_]+)"/g)].map(m=>m[1]);for(const name of ['calendar_theme_changed','friend_added','shift_name_changed','shift_color_changed','schedule_edited','schedule_deleted','schedule_notification_changed','backup_restored','sleep_record_edited'])assert.ok(names.includes(name),name);for(const [name,meta] of Object.entries(EVENT_META)){if(meta.retired||meta.group==='system'||/^(ops_|alarm_schedule_|alarm_refresh_|device_boot_)/.test(name)||['alarm_fired','auto_backup_created'].includes(name))assert.ok(!names.includes(name),name);else assert.ok(names.includes(name),name);}});

test('weekday DAU uses selected completed period, includes zero, excludes missing and future', () => { const docs={series:{dates:['2026-09-21','2026-09-28','2026-10-05','2026-10-06','2026-10-07','2026-10-08','2026-10-12'],dau:[100,10,0,null,8,NaN,999]}};const rows=weekdayDauAverages(docs,30,'2026-10-11');assert.deepEqual(rows[0],{label:'월',count:3,average:110/3});assert.deepEqual(rows[1],{label:'화',count:0,average:null});assert.equal(rows[2].average,8);assert.equal(rows[3].count,0);const week=weekdayDauAverages(docs,7,'2026-10-11');assert.deepEqual(week[0],{label:'월',count:1,average:0});});


test('one country table separates languages within the same country', () => {
  const docs=buildMockDocs();
  for (const range of [7,30,100,365]) {
    const view=computeView(docs,range);const key=JSON.stringify(['United States','Korean']);
    const html=countryCard(docs,view,{country:key,marketSort:'activeUsers'});
    assert.match(html,/<th>국가<\/th><th>언어<\/th>/);
    assert.equal((html.match(/class="ops-table market-table"/g)||[]).length,1);
    assert.equal(html.includes('ch-language'),false);
    assert.match(html,/미국 \/ 한국어/);
    assert.match(html,/남아프리카공화국/);
    assert.match(html,/<th>알람 생성<\/th>/);
    assert.match(html,/id="ch-country"/);
  }
  docs.operations.byRange[30].countryLanguages=null;
  assert.match(countryCard(docs,computeView(docs,30),{}),/아직 연결되지/);
});
test('country-language metrics and events use joint dimensions, never join separate totals', () => {
  const ga=new Ga4({auth:null});const dims=['country','language'];
  for (const query of [ga.segmentSummary(dims,'a','b'),ga.segmentEvents(dims,'a','b'),ga.countryLanguageDaily()]) {
    assert.match(JSON.stringify(query.dimensionFilter),new RegExp(DEFAULTS.streamId));
    assert.ok(query.dimensions.some(d=>d.name==='country'));
    assert.ok(query.dimensions.some(d=>d.name==='language'));
  }
  const r=report(['activeUsers'],[[['United States','Korean'],[3]],[['United States','English'],[9]]]);
  const e=report(['eventCount','totalUsers'],[[['United States','Korean','alarm_template_saved'],[12,2]],[['United States','English','alarm_template_saved'],[5,4]]]);
  const rows=segmentStats(r,e,2);
  assert.equal(rows[0].events.alarm_template_saved.users,2);assert.equal(rows[1].events.alarm_template_saved.users,4);
  assert.notEqual(rows[0].name,rows[1].name);assert.equal(rows[0].country,'United States');assert.equal(rows[0].language,'Korean');
  const daily=report(['activeUsers','newUsers','sessions'],[[['20261001','United States','Korean'],[3,1,4]],[['20261001','United States','English'],[9,2,12]]]);
  const trend=countryTrend(daily,100,2);
  assert.deepEqual(trend.series[JSON.stringify(['United States','Korean'])].dau,[3]);
  assert.deepEqual(trend.series[JSON.stringify(['United States','English'])].dau,[9]);
});


test('country total ranks groups, keeping small language rows above the next country', () => {
  const period={countries:[{name:'South Korea',activeUsers:100,newUsers:12},{name:'United States',activeUsers:50,newUsers:5}],countryLanguages:[
    {country:'United States',language:'English',activeUsers:50,newUsers:5},
    {country:'South Korea',language:'English',activeUsers:1,newUsers:1},
    {country:'South Korea',language:'Korean',activeUsers:99,newUsers:11}]};
  assert.deepEqual(groupedCountryRows(period).map(r=>[r.country,r.language]),[['South Korea','Korean'],['South Korea','English'],['United States','English']]);
  assert.deepEqual(groupedCountryRows(period,'newUsers').map(r=>r.country),['South Korea','South Korea','United States']);
});
