import test from 'node:test';
import assert from 'node:assert/strict';
import { acquisitionQuery, activationQuery, retentionQuery, channelTotals, parseFunnel, parseRetention, trafficKey, shiftDate } from '../lib/growth.mjs';
const report = (dimensions, metrics, rows) => ({ dimensionHeaders: dimensions.map(name => ({name})), metricHeaders: metrics.map(name=>({name})), rows: rows.map(([d,m]) => ({dimensionValues:d.map(value=>({value})),metricValues:m.map(value=>({value:String(value)}))})) });
test('paid Google attribution takes priority; direct and unassigned never become organic', () => {
  assert.equal(trafficKey({firstUserSourcePlatform:'Google Ads',firstUserDefaultChannelGroup:'Organic Search'}),'ads');
  for(const channel of ['Direct','Unassigned','(not set)','']) assert.equal(trafficKey({firstUserDefaultChannelGroup:channel}),'unknown');
  const r=report(['firstUserDefaultChannelGroup','firstUserSourcePlatform'],['newUsers'],[[['Cross-network','Google Ads'],[3]],[['Organic Search','Manual'],[4]],[['Direct','(not set)'],[7]]]);
  assert.deepEqual(channelTotals(r),{ads:3,organic:4,otherPaid:0,unknown:7,other:0});
  assert.equal(channelTotals(null),null);
});
test('all acquisition and cohort requests restrict the production stream', () => {
  for(const mode of ['channels','countries','campaigns','daily']) assert.equal(acquisitionQuery('prod','2026-10-01','2026-10-14',mode).dimensionFilter.filter.stringFilter.value,'prod');
  const r=retentionQuery('prod','2026-10-14',7,'ads');
  assert.deepEqual(r.cohortSpec.cohorts[0].dateRange,{startDate:'2026-10-01',endDate:'2026-10-07'});
  assert.match(JSON.stringify(r.dimensionFilter),/prod/);
  assert.match(JSON.stringify(r.dimensionFilter),/Google Ads/);
  assert.equal(r.cohortSpec.cohortsRange.startOffset,0);
});
test('activation is closed, first-open based, with 24-hour observation beyond last entrant date', () => {
  const r=activationQuery('prod','2026-10-08','2026-10-14');
  assert.equal(r.funnel.isOpenFunnel,false);
  assert.equal(r.funnel.steps[1].withinDurationFromPriorStep,'86400s');
  assert.equal(r.funnel.steps[0].filterExpression.andGroup.expressions[1].funnelFieldFilter.betweenFilter.toValue.int64Value,'20261013');
  assert.match(JSON.stringify(r),/first_open/);
  assert.equal(shiftDate('2026-03-01',-1),'2026-02-28');
});
test('funnel ratio uses sequential users; failed/empty/limited reports stay distinct', () => {
  const r={funnelTable:report(['funnelStepName'],['activeUsers'],[[['1. First open'],[10]],[['2. Schedule ready'],[4]]])};
  assert.equal(parseFunnel(r,'2026-10-01','2026-10-14').rate,.4);
  assert.equal(parseFunnel(null,'2026-10-01','2026-10-14').entrants,null);
  r.funnelTable.metadata={subjectToThresholding:true};
  assert.equal(parseFunnel(r,'2026-10-01','2026-10-14').rate,null);
});
test('retention uses cohort total, hides rates with zero or limited denominator', () => {
  const r=report(['cohort','cohortNthDay'],['cohortActiveUsers','cohortTotalUsers'],[[['recent','0007'],[3,10]]]);
  assert.equal(parseRetention(r,'2026-10-14',7).rate,.3);
  assert.equal(parseRetention(null,'2026-10-14',7).rate,null);
  assert.equal(parseRetention({rows:[]},'2026-10-14',7).size,0);
  r.metadata={subjectToThresholding:true};
  assert.equal(parseRetention(r,'2026-10-14',7).rate,null);
});
test('live funnel duplicated headers preserve populated values', () => {
 const r={funnelTable:report(['funnelStepName'],['activeUsers','completion','abandoned','rate','activeUsers','completion','abandoned','rate'],[[['1. First open'],[41,.4146,24,.5854]],[['2. Schedule ready'],[17,1,0,0]]])};
 assert.equal(parseFunnel(r,'2026-10-08','2026-10-14').entrants,41);
 assert.equal(parseFunnel(r,'2026-10-08','2026-10-14').rate,17/41);
});
test('ASO compares complete equal windows, excludes publish day, and rejects impossible counts', async () => {
 const {asoComparison,validStoreComparison}=await import('../../public/assets/js/growth.js');
 const g={latest:'2026-10-14',daily:[{date:'20261001',firstUserDefaultChannelGroup:'Organic Search',newUsers:4},{date:'20261007',firstUserDefaultChannelGroup:'Organic Search',newUsers:99},{date:'20261008',firstUserDefaultChannelGroup:'Organic Search',newUsers:6},{date:'20261008',firstUserDefaultChannelGroup:'Direct',newUsers:50}],coverage:{}};
 const c=asoComparison(g,'2026-10-07'); assert.equal(c.before.users,4);assert.equal(c.after.users,6);assert.equal(c.delta,.5);
 assert.equal(asoComparison(g,'2026-10-08').status,'waiting');
 assert.equal(validStoreComparison({beforeVisitors:5,beforeInstalls:6,afterVisitors:5,afterInstalls:1}),false);
 assert.equal(validStoreComparison({beforeVisitors:0,beforeInstalls:0,afterVisitors:5,afterInstalls:1}),true);
});
test('retention selects requested day rather than day-zero row', () => {
 const r=report(['cohort','cohortNthDay'],['cohortActiveUsers','cohortTotalUsers'],[[['recent','0000'],[41,41]],[['recent','0001'],[17,41]]]);
 assert.equal(parseRetention(r,'2026-10-14',1).rate,17/41);
});
