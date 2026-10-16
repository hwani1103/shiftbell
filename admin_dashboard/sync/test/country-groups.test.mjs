import test from 'node:test';
import assert from 'node:assert/strict';
import { mergeUnknownCountryReport,hasUnknownCountry } from '../lib/unknown-countries.mjs';
import { Ga4,DEFAULTS } from '../lib/ga4.mjs';
import { countryCard,groupedCountryRows,COUNTRY_FEATURES } from '../../public/assets/js/operations.js';
import { buildMockDocs } from '../../public/assets/js/mock.js';
import { computeView } from '../../public/assets/js/views.js';
const report=rows=>({rows:rows.map(([d,m])=>({dimensionValues:d.map(value=>({value})),metricValues:m.map(value=>({value:String(value)}))}))});
test('unknown-country union keeps GA4 distinct users instead of adding buckets',()=>{
  const original=report([[['','English'],[8]],[['(not set)','English'],[4]],[['South Korea','Korean'],[100]]]);
  const union=report([[['English'],[9]]]);
  assert.equal(hasUnknownCountry(original),true);
  const merged=mergeUnknownCountryReport(original,union);
  assert.equal(merged.rows.length,2);
  assert.deepEqual(merged.rows[1].dimensionValues,[{value:'(not set)'},{value:'English'}]);
  assert.equal(merged.rows[1].metricValues[0].value,'9');
  assert.equal(mergeUnknownCountryReport(original,null),original);
});
test('unknown daily union retains date and language axes, plus query coverage',()=>{
  const original=report([[['20261012','','English'],[8]],[['20261012','(not set)','English'],[4]]]);
  original.rowCount=3;
  const merged=mergeUnknownCountryReport(original,report([[['20261012','English'],[9]]]),1);
  assert.deepEqual(merged.rows[0].dimensionValues.map(d=>d.value),['20261012','(not set)','English']);
  assert.equal(merged.metadata.sourceTruncated,true);
});
test('union queries use EmptyFilter and preserve production stream and feature filters',()=>{
  const ga=new Ga4({auth:null});
  const query=ga.unknownCountries(ga.segmentEvents(['country','language'],'a','b'));
  assert.deepEqual(query.dimensions.map(d=>d.name),['language','eventName']);
  const json=JSON.stringify(query.dimensionFilter);
  assert.match(json,new RegExp(DEFAULTS.streamId));assert.match(json,/emptyFilter/);
  for(const [name] of COUNTRY_FEATURES)assert.match(json,new RegExp(name));
});
test('country table uses one spanning country cell and expanded features without alarm dismissal',()=>{
  const docs=buildMockDocs();const html=countryCard(docs,computeView(docs,30),{});
  assert.equal((html.match(/<th scope="rowgroup" rowspan="2">대한민국<\/th>/g)||[]).length,1);
  assert.match(html,/<th>신규 사용자<\/th>/);
  for(const [,label] of COUNTRY_FEATURES)assert.ok(html.includes('<th>'+label+'</th>'),label);
  assert.equal(html.includes('<th>알람 끄기</th>'),false);
  assert.equal(html.includes('스토어 신규 설치 수와 다릅니다'),true);
});
test('missing and not-set countries share one display group without duplicate country cells',()=>{
  const docs=buildMockDocs();const period=docs.operations.byRange[30];
  period.countries=[{name:'South Korea',activeUsers:20},{name:'(not set)',activeUsers:10}];
  period.countryLanguages=[{name:'a',country:'(missing)',language:'English',activeUsers:5,newUsers:2},{name:'b',country:'South Korea',language:'Korean',activeUsers:20,newUsers:3},{name:'c',country:'(not set)',language:'Korean',activeUsers:4,newUsers:2}];
  assert.deepEqual(groupedCountryRows(period).map(r=>r.name),['b','a','c']);
  const html=countryCard(docs,computeView(docs,30),{});
  assert.equal((html.match(/<th scope="rowgroup" rowspan="2">확인 불가<\/th>/g)||[]).length,1);
  assert.equal(html.includes('미제공'),false);
});
