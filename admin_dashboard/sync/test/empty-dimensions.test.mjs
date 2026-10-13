import test from 'node:test';
import assert from 'node:assert/strict';
import { Firestore } from '@google-cloud/firestore';
import { countryTrend, segmentStats } from '../lib/operations.mjs';
import { buildEvents, buildEventSummary } from '../lib/transform.mjs';
import { emptyDimensions, assertNonemptyFields } from '../lib/report-values.mjs';
const report = (dims, rows) => ({ dimensionHeaders: dims.map(name => ({name})), metricHeaders: [{name:'activeUsers'}], rows: rows.map(([d,m]) => ({dimensionValues:d.map(value=>({value})),metricValues:m.map(value=>({value:String(value)}))})) });

test('missing country labels preserve totals and serialize with the real Firestore SDK', () => {
  const trend=countryTrend(report(['date','country'],[[['20261011',''],[3,1,4]],[['20261011','(not set)'],[2,0,2]]]));
  assert.deepEqual(trend.series['(not set)'].dau,[5]);
  assert.equal(trend.availableCountries,1);
  const segments=segmentStats(report(['country'],[[[''],[5]]]),report(['country','eventName'],[[['','alarm_template_saved'],[2,1]],[['',''],[9,1]]]));
  assert.equal(segments[0].name,'(not set)');
  assert.equal(segments[0].events.alarm_template_saved.count,2);
  assert.equal(Object.hasOwn(segments[0].events,''),false);
  const joint=segmentStats(report(['country','language'],[[['',''],[5]]]),null,2);
  assert.equal(joint[0].country,'(not set)');
  assert.equal(joint[0].language,'(not set)');
  const db=new Firestore({projectId:'offline-diagnostic'});
  // batch.set performs the production SDK's field validation without any network/commit.
  assert.doesNotThrow(()=>db.batch().set(db.doc('diagnostic/empty-country'),{trend,segments,joint}));
});

test('blank event names are excluded without changing named event counts', () => {
  const events=buildEvents({dates:['2026-10-11'],eventsDaily:report(['date','eventName'],[[['20261011',''],[10]],[['20261011','alarm_template_saved'],[4]],[['20261011',undefined],[2]]])});
  assert.deepEqual(events.totals,{alarm_template_saved:4});
  assert.deepEqual(buildEventSummary(report(['eventName'],[[[''],[10,2]],[['alarm_template_saved'],[4,1]]])),[{name:'alarm_template_saved',count:4,users:1}]);
  const db=new Firestore({projectId:'offline-diagnostic'});
  assert.doesNotThrow(()=>db.batch().set(db.doc('diagnostic/events'),events));
});

test('empty dimensions diagnostics identify nested source and column without values', () => {
  const raw={countryDaily:report(['date','country'],[[['20261011',''],[2,0,2]]]),operationsByRange:{7:{countryEvents:report(['country','eventName'],[[['South Korea',''],[3,1]]])}}};
  assert.deepEqual(emptyDimensions(raw),[{report:'countryDaily',column:'country',count:1},{report:'operationsByRange.7.countryEvents',column:'eventName',count:1}]);
  assert.throws(()=>assertNonemptyFields({series:{'':{dau:[1]}}},'operations'),/operations\["series"\]\[""\]/);
});
