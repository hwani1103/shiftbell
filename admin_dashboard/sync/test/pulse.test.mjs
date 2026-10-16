import test from 'node:test';
import assert from 'node:assert/strict';
import { newcomersQuery, newcomerRows, retentionTrendQuery, retentionTrend, fetchPulse } from '../lib/pulse.mjs';
import { FEATURE_NAMES, comparisonRows } from '../../public/assets/js/pulse-model.js';
import { pulseHero, newcomerCard, featureComparison } from '../../public/assets/js/pulse.js';
import { buildMockDocs } from '../../public/assets/js/mock.js';
const report = (ds,ms,rs) => ({dimensionHeaders:ds.map(name=>({name})),metricHeaders:ms.map(name=>({name})),rows:rs.map(([d,m])=>({dimensionValues:d.map(value=>({value})),metricValues:m.map(value=>({value:String(value)}))}))});
test('newcomers are restricted to prod, first-session window and named activities',()=>{
  const q=newcomersQuery('prod','2026-09-17','2026-10-16');
  assert.deepEqual(q.dimensions.map(x=>x.name),['firstSessionDate','country','language','eventName']);
  assert.match(JSON.stringify(q.dimensionFilter),/prod/);
  assert.match(JSON.stringify(q.dimensionFilter),/20260917/);
  const dates=q.dimensionFilter.andGroup.expressions[1].andGroup.expressions[0].filter;
  assert.equal(dates.inListFilter.values.length,30);
  assert.equal(dates.inListFilter.values.at(-1),'20261016');
  assert.equal(dates.betweenFilter,undefined);
  for (const name of ['schedule_created','sleep_record_saved','all_shifts_opened','memo_saved']) assert.ok(FEATURE_NAMES.includes(name));
  assert.ok(!FEATURE_NAMES.includes('alarm_fired'));
});
test('newcomer completion and feature people are cohort activities, not unrelated daily totals',()=>{
  const r=report(['firstSessionDate','country','language','eventName'],['totalUsers','eventCount'],[
    [['20261015','Brazil','Portuguese','first_open'],[2,2]],
    [['20261015','Brazil','Portuguese','onboarding_complete'],[1,3]],
    [['20261015','Brazil','Portuguese','memo_saved'],[1,7]],
    [['20261014','','','first_open'],[1,1]],
  ]);
  const rows=newcomerRows(r); assert.equal(rows[0].completed,1); assert.equal(rows[0].features.memo_saved,1);
  assert.equal(rows[1].country,'(missing)'); assert.equal(newcomerRows(null),null);
});
test('D7 rolling cohorts are mature, isolate rows and retain source limitations',()=>{
  const q=retentionTrendQuery('prod','2026-10-15');
  assert.equal(q.cohortSpec.cohorts.length,8);
  assert.deepEqual(q.cohortSpec.cohorts.at(-1).dateRange,{startDate:'2026-10-02',endDate:'2026-10-08'});
  const r=report(['cohort','cohortNthDay'],['cohortActiveUsers','cohortTotalUsers'],[[['d20261015','0007'],[3,10]],[['d20261014','0007'],[1,20]]]);
  assert.equal(retentionTrend(r,'2026-10-15').at(-1).rate,.3);
  assert.equal(retentionTrend(r,'2026-10-15').at(-2).rate,.05);
  r.rowCount=20;assert.equal(retentionTrend(r,'2026-10-15').at(-1).rate,null);
});
test('feature comparison sorts by two-day total and separates unseen from observed zero',()=>{
  const docs={pulse:{today:'2026-10-16',events:[{date:'2026-10-14',name:'memo_saved',count:2},{date:'2026-10-15',name:'schedule_created',count:4},{date:'2026-10-16',name:'sleep_record_saved',count:7}],coverage:{events:{status:'available'}}}};
  const m=comparisonRows(docs);assert.equal(m.rows[0].name,'sleep_record_saved');
  assert.deepEqual(m.rows.find(r=>r.name==='memo_saved').values,[0,0]);
  assert.deepEqual(m.rows.find(r=>r.name==='all_shifts_opened').values,[null,null]);
  assert.deepEqual(comparisonRows(docs,'closed').dates,['2026-10-14','2026-10-15']);
  docs.pulse.events=null;assert.equal(comparisonRows(docs).available,false);
});
test('optional API failure preserves unavailable states and includes current KST date',async()=>{
  const calls=[];const ga={streamId:'prod',coreDaily:()=>({}),eventsDaily:()=>({}),tryReport:async(name,q)=>{calls.push(q);return null;}};
  const p=await fetchPulse(ga,new Date('2026-10-15T16:00:00Z'),'2026-10-15',{log(){}});
  assert.equal(p.today,'2026-10-16');assert.equal(p.daily,null);assert.equal(p.newcomers,null);
  assert.equal(p.coverage.events.status,'unavailable');assert.equal(calls.length,4);
});
test('views handle old docs, unavailable reports, all features and escaped country labels',()=>{
  const docs=buildMockDocs({today:'2026-10-16'}),ui={range:30};
  assert.match(pulseHero(docs,ui),/온보딩 완료율/);
  assert.match(featureComparison(docs,{...ui,featureAll:true}),/수면 기록/);
  docs.pulse.newcomers[0].country='<script>alert(1)</script>';
  assert.ok(!newcomerCard(docs,{newcomerDate:docs.pulse.newcomers[0].date}).includes('<script>'));
  delete docs.pulse;assert.doesNotThrow(()=>pulseHero(docs,ui));
});
