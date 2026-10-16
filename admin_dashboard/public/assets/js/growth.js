import { esc, fmtInt, fmtPct, fmtMD } from './format.js';
import { localizeName, COLORS } from './labels.js';
import { lineChart } from './charts.js';

export const CHANNELS = { ads: 'Google Ads', organic: '검색 자연유입', otherPaid: '기타 광고', unknown: '직접·출처 불명', other: '추천·기타 유입' };
const scopes = [['all', '전체 유입'], ['ads', 'Google Ads'], ['organic', '검색 자연유입']];
const count = n => n == null ? '—' : fmtInt(n);
const rate = n => n == null ? '—' : fmtPct(n, 1);
const dates = (from, to) => esc(fmtMD(from)) + '–' + esc(fmtMD(to));
const panel = (title, sub, body, cls = '') => `<section class="card span-12 ${cls}"><div class="card-h"><div><h2>${title}</h2><p>${sub}</p></div></div>${body}</section>`;
export const disclosure = (title, html) => `<details class="dashboard-details span-12"><summary>${title}</summary><div class="ops-layout">${html}</div></details>`;
const empty = message => `<p class="empty-state">${message}</p>`;
const limited = state => state?.thresholded || state?.sampled || state?.truncated || state?.otherRowLoss;
const status = (s, size) => s === 'unavailable' ? '집계 확인 필요' : s === 'limited' ? '집계 제한' : !size ? '관측된 사용자 없음' : size < 30 ? '표본 적음' : '집계됨';
export const addDay = (date, n) => new Date(Date.parse(date + 'T00:00:00Z') + n * 86400000).toISOString().slice(0, 10);
export function trafficKey(row) {
  if (row.firstUserSourcePlatform === 'Google Ads') return 'ads';
  const ch = row.firstUserDefaultChannelGroup || '';
  if (ch === 'Organic Search') return 'organic';
  if (/Paid|Cross-network|Display|Audio/i.test(ch)) return 'otherPaid';
  if (['', 'Direct', 'Unassigned', '(not set)', '(other)'].includes(ch)) return 'unknown';
  return 'other';
}
export function trafficDays(growth, range) {
  if (!growth?.daily || !growth.latest) return null;
  const from = addDay(growth.latest, 1 - Math.min(range, 100));
  const rows = new Map();
  for (let d = from; d <= growth.latest; d = addDay(d, 1)) rows.set(d, Object.fromEntries(Object.keys(CHANNELS).map(k => [k, 0])));
  for (const row of growth.daily) {
    const raw = row.date;
    const date = /^\d{8}$/.test(raw) ? raw.slice(0, 4) + '-' + raw.slice(4, 6) + '-' + raw.slice(6) : raw;
    if (rows.has(date)) rows.get(date)[trafficKey(row)] += row.newUsers;
  }
  return { dates: [...rows.keys()], series: Object.fromEntries(Object.keys(CHANNELS).map(k => [k, [...rows.values()].map(r => r[k])])) };
}
export function asoComparison(growth, date) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date || '') || Number.isNaN(Date.parse(date))) return { status: 'no-date' };
  const before = { from: addDay(date, -7), to: addDay(date, -1) };
  const after = { from: addDay(date, 1), to: addDay(date, 7) };
  if (!growth?.latest || !growth.daily || limited(growth.coverage?.daily)) return { status: 'unavailable', before, after };
  if (after.to > growth.latest) return { status: 'waiting', before, after };
  const daily = trafficDays(growth, 100);
  if (before.from < daily.dates[0]) return { status: 'outside', before, after };
  const sum = window => daily.dates.reduce((n, d, i) => n + (d >= window.from && d <= window.to ? daily.series.organic[i] : 0), 0);
  before.users = sum(before); after.users = sum(after);
  return { status: 'ready', before, after, delta: before.users > 0 ? (after.users - before.users) / before.users : null };
}
export function growthCard(docs, ui) {
  const growth = docs.growth; const data = growth?.byRange?.[ui.range];
  if (!data) return panel('유입 · 성장', '광고와 자연유입을 같은 기준으로 비교합니다.', empty('성장 지표를 준비 중입니다. 다음 집계 후 표시됩니다.'));
  const scope = ui.traffic || 'all'; const channels = data.channels;
  const funnel = data.activation?.[scope];
  const ret = growth.retention?.[scope]?.[7];
  const incoming = channels == null ? null : scope === 'all' ? Object.values(channels).reduce((a, b) => a + b, 0) : channels[scope];
  const tiles = [
    ['신규 사용자', count(incoming) + (incoming == null ? '' : '명'), dates(data.from, data.to) + ' · GA4 첫 유입'],
    ['24시간 내 설정 완료', rate(funnel?.rate), funnel ? `${count(funnel.completed)} / ${count(funnel.entrants)}명 · ${dates(funnel.from, funnel.to)} 첫 실행` : '집계 확인 필요'],
    ['D7 재방문', rate(ret?.rate), ret ? `${count(ret.returned)} / ${count(ret.size)}명 · ${dates(ret.from, ret.to)} 첫 세션` : '집계 확인 필요'],
  ];
  let body = `<div class="growth-tabs" role="group" aria-label="유입 경로">${scopes.map(([key, label]) => `<button data-action="traffic" data-key="${key}" aria-pressed="${key === scope}">${label}</button>`).join('')}</div>`;
  body += `<div class="growth-metrics">${tiles.map(([label, value, note]) => `<article><span>${label}</span><b>${value}</b><small>${note}</small></article>`).join('')}</div>`;
  body += `<p class="sub">설정 완료는 첫 실행 → 근무표 설정 완료를 같은 사람 기준으로 연결합니다. 마지막 첫 실행일 이후 24시간을 관측하며, D7은 7일이 지난 별도 집단입니다. 신규 사용자 수를 설정률의 분모로 대신 사용하지 않습니다.</p>`;
  if (funnel && (funnel.status !== 'available' || funnel.entrants < 30)) body += `<p class="growth-note">설정 완료: ${status(funnel.status, funnel.entrants)}${funnel.status === 'unavailable' ? ' · 데이터 조회를 확인한 후 판단하세요.' : ' · 비율의 작은 차이로 광고 성과를 단정하지 마세요.'}</p>`;
  if (limited(data.coverage?.channels)) body += '<p class="growth-note">유입 보고서에 집계 제한이 있습니다. 표시된 사용자 수는 완전한 전체 수가 아닐 수 있습니다.</p>';
  return panel('유입 · 성장', `${dates(data.from, data.to)} · 광고 / 검색 자연유입 / 출처 불명을 구분`, body, 'growth-hero');
}
export function acquisitionCard(docs, ui) {
  const growth = docs.growth; const data = growth?.byRange?.[ui.range];
  if (!data) return '';
  const total = data.channels && Object.values(data.channels).reduce((a,b) => a+b, 0);
  const rows = Object.entries(CHANNELS).map(([key, label]) => `<tr><th>${label}</th><td>${count(data.channels?.[key])}명</td><td>${total > 0 ? rate(data.channels[key] / total) : '—'}</td></tr>`).join('');
  return panel('어디서 들어왔나요?', '처음 유입된 경로 기준 · 다시 방문해도 같은 출처로 비교', `<div class="growth-split"><div class="table-scroll"><table class="ops-table"><thead><tr><th>유입 경로</th><th>신규 사용자</th><th>비중</th></tr></thead><tbody>${rows}</tbody></table></div><div><div id="ch-acquisition" style="min-height:240px"></div><p class="sub">최근 ${Math.min(ui.range,100)}일 · 광고 / 검색 자연유입 / 직접·출처 불명</p></div></div><p class="sub">직접·출처 불명을 자연유입으로 간주하지 않습니다. ‘검색 자연유입’은 GA4의 Organic Search이며 Play 스토어 검색·탐색 방문 전체와 같지 않습니다.</p>`);
}
export function activationCard(docs, ui) {
  const data = docs.growth?.byRange?.[ui.range]; if (!data) return '';
  const rows = scopes.map(([key, label]) => {
    const f = data.activation?.[key]; const d1 = docs.growth.retention?.[key]?.[1]; const d7 = docs.growth.retention?.[key]?.[7];
    return `<tr><th>${label}</th><td>${count(f?.entrants)}</td><td>${count(f?.completed)}</td><td>${rate(f?.rate)}</td><td>${rate(d1?.rate)}<small>${count(d1?.returned)} / ${count(d1?.size)}명</small></td><td>${rate(d7?.rate)}<small>${count(d7?.returned)} / ${count(d7?.size)}명</small></td></tr>`;
  }).join('');
  const d1=docs.growth.retention?.all?.[1],d7=docs.growth.retention?.all?.[7];
  return panel('들어온 뒤 실제로 사용하나요?', '설정 완료와 재방문을 함께 확인', `<div class="table-scroll"><table class="ops-table growth-table"><thead><tr><th>유입</th><th>첫 실행</th><th>설정 완료</th><th>완료율</th><th>D1 재방문</th><th>D7 재방문</th></tr></thead><tbody>${rows}</tbody></table></div><p class="sub">D1: ${d1 ? dates(d1.from,d1.to) : '—'} 첫 세션 / D7: ${d7 ? dates(d7.from,d7.to) : '—'} 첫 세션. 각 날짜까지 충분히 관측된 최근 7일 유입 집단이며 상단 조회 기간과 별도입니다. 표본 30명 미만은 방향 참고용입니다.</p><details class="growth-help"><summary>설정 완료와 알람 지표의 의미</summary><p>설정 완료는 첫 실행 이후 24시간 안에 온보딩을 마친 사람입니다. 근무표 재설정만 한 기존 사용자를 신규 완료 인원에 섞지 않습니다. 알람 템플릿의 최초 설정 여부와 실제 예약 성공은 이 지표가 보장하지 않습니다. 기존 ‘알람 생성’ 표시는 ‘고정 알람 저장’으로 정정했습니다.</p></details>`);
}
export function growthCountries(docs, ui) {
  const source=docs.growth?.byRange?.[ui.range]?.countries;
  if(source==null)return panel('국가별 신규 유입','광고·검색 자연유입의 국가 분포',empty('국가별 유입 집계를 확인 중입니다.'));
  const map=new Map();
  for(const r of source){const key=r.country||'(not set)';if(!map.has(key))map.set(key,{country:key,total:0,ads:0,organic:0,unknown:0,other:0});const row=map.get(key);row.total+=r.newUsers;const k=trafficKey(r);row[k==='otherPaid'?'other':k]+=r.newUsers;}
  const all=[...map.values()].sort((a,b)=>b.total-a.total);
  const table=rows=>`<div class="table-scroll"><table class="ops-table"><thead><tr><th>국가</th><th>신규</th><th>Google Ads</th><th>검색 자연</th><th>직접·불명</th><th>기타</th></tr></thead><tbody>${rows.map(r=>`<tr><th>${esc(localizeName('country',r.country))}</th><td>${count(r.total)}</td><td>${count(r.ads)}</td><td>${count(r.organic)}</td><td>${count(r.unknown)}</td><td>${count(r.other)}</td></tr>`).join('')}</tbody></table></div>`;
  return panel('국가별 신규 유입','신규 사용자 순 · 출처별 국가 분포',all.length?table(all.slice(0,8))+(all.length>8?`<details class="growth-help"><summary>나머지 ${all.length-8}개 국가</summary>${table(all.slice(8))}</details>`:''):empty('관측된 신규 사용자가 없습니다.'));
}
export function campaignCard(docs,ui){
  const rows=docs.growth?.byRange?.[ui.range]?.campaigns;
  return panel('Google Ads · 캠페인','광고로 들어온 신규 사용자의 캠페인 이름',rows==null?empty('캠페인 집계를 확인 중입니다.'):rows.length?`<div class="table-scroll"><table class="ops-table"><thead><tr><th>캠페인</th><th>신규 사용자</th></tr></thead><tbody>${[...rows].sort((a,b)=>b.newUsers-a.newUsers).map(r=>`<tr><th>${esc(r.firstUserCampaignName||'이름 확인 불가')}</th><td>${count(r.newUsers)}</td></tr>`).join('')}</tbody></table></div><p class="sub">최초 유입 캠페인 기준입니다. 광고비·설치 전환과 귀속 기준이 다를 수 있어 이 수치를 Ads 설치 수로 대체하지 않습니다.</p>`:empty('선택 기간에 Google Ads로 확인된 신규 유입이 없습니다. 광고 시작 후 자동으로 채워집니다.'))+`<p class="span-12 growth-link"><a href="https://ads.google.com/" target="_blank" rel="noopener">Google Ads에서 광고비·전환 확인 ↗</a> · 광고비가 연결되기 전에는 비용 대비 수익을 표시하지 않습니다.</p>`;
}
export function validStoreComparison(values){
  const names=['beforeVisitors','beforeInstalls','afterVisitors','afterInstalls'];
  if(names.some(k=>values[k]===''||values[k]==null||!Number.isSafeInteger(Number(values[k]))||Number(values[k])<0))return false;
  return Number(values.beforeInstalls)<=Number(values.beforeVisitors)&&Number(values.afterInstalls)<=Number(values.afterVisitors);
}
export function asoCard(docs,ui){
  const cmp=asoComparison(docs.growth,ui.asoDate); const saved=ui.storeComparison;
  let result=cmp.status==='no-date'?'실제 게시일을 기록하면 게시 전후 각각 7일의 검색 자연유입을 비교합니다.':cmp.status==='waiting'?`게시 후 관측 중 · ${esc(cmp.after.to)}까지 집계되면 7일 비교가 완성됩니다.`:cmp.status==='outside'?'게시 전 기간이 최근 100일 보관 범위를 벗어났습니다.':cmp.status==='unavailable'?'자연유입 집계가 준비되면 전후 비교를 표시합니다.':`게시 전 ${count(cmp.before.users)}명 → 게시 후 ${count(cmp.after.users)}명${cmp.delta==null?' · 이전 유입 0명':` · ${cmp.delta>=0?'+':''}${fmtPct(cmp.delta,1)}`}`;
  const storeReady=validStoreComparison(saved||{})&&saved.date===ui.asoDate;
  const storeResult=storeReady?`<div class="growth-metrics"><article><span>게시 전 스토어 전환율</span><b>${Number(saved.beforeVisitors)>0?rate(Number(saved.beforeInstalls)/Number(saved.beforeVisitors)):'—'}</b><small>${count(Number(saved.beforeInstalls))} 획득 / ${count(Number(saved.beforeVisitors))} 방문</small></article><article><span>게시 후 스토어 전환율</span><b>${Number(saved.afterVisitors)>0?rate(Number(saved.afterInstalls)/Number(saved.afterVisitors)):'—'}</b><small>${count(Number(saved.afterInstalls))} 획득 / ${count(Number(saved.afterVisitors))} 방문</small></article></div>`:'';
  return panel('ASO · 자연유입의 변화','실제 게시일을 기준으로 같은 요일의 7일 전후를 비교',`<form id="aso-date" class="growth-form"><label>실제 게시일<input class="input" type="date" name="date" value="${esc(ui.asoDate||'')}" max="${new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Seoul'})}" required></label><button class="btn sm" type="submit">게시일 기록</button></form><p class="growth-note">${result}</p>${cmp.before?`<p class="sub">게시 전 ${dates(cmp.before.from,cmp.before.to)} / 게시 후 ${dates(cmp.after.from,cmp.after.to)} · 게시 당일은 제외합니다.</p>`:''}<p class="sub">이 비교는 GA4 검색 자연유입의 변화입니다. 광고·국가·요일 구성과 다른 업데이트의 영향이 섞일 수 있어 ASO의 인과 효과로 단정하지 않습니다.</p><details class="growth-help"><summary>Play 스토어 방문·설치 전환도 비교하기</summary><p>Play Console에서 동일 국가와 동일 자연유입 경로(검색 또는 탐색)를 선택하고 위 두 기간의 등록정보 방문자·획득 수를 기록하세요.</p><a href="https://play.google.com/console/u/1/developers/6051598437272243988/app/4972031974484074779" target="_blank" rel="noopener">Play Console 열기 ↗</a><form id="aso-store" class="growth-store-form">${[['beforeVisitors','게시 전 방문자'],['beforeInstalls','게시 전 획득'],['afterVisitors','게시 후 방문자'],['afterInstalls','게시 후 획득']].map(([key,label])=>`<label>${label}<input class="input" name="${key}" type="number" min="0" step="1" required value="${esc(storeReady?saved[key]:'')}"></label>`).join('')}<label class="growth-scope">비교 범위<input class="input" name="scope" placeholder="예: 한국 · Play 검색" required maxlength="100" value="${esc(storeReady?saved.scope:'')}"></label><button class="btn sm" type="submit">전환 기록</button></form><p id="aso-form-message" role="status" class="sub"></p>${storeResult}${storeReady?`<p class="sub">범위: ${esc(saved.scope)} · 직접 기록한 Play Console 수치</p>`:''}</details><p class="sub">게시일과 직접 기록한 스토어 수치는 이 브라우저에 보관됩니다. 심사 제출일을 게시일로 사용하지 마세요.</p>`);
}
export function mountAcquisition(root,docs,ui){
  const node=root.querySelector('#ch-acquisition');const values=trafficDays(docs.growth,ui.range);if(!node||!values)return null;
  return lineChart(node,{dates:values.dates,series:[{key:'ads',label:'Google Ads',values:values.series.ads,color:COLORS.ads},{key:'organic',label:'검색 자연유입',values:values.series.organic,color:COLORS.dau},{key:'unknown',label:'직접·출처 불명',values:values.series.unknown,color:COLORS.palette[3]}],title:'유입 경로별 신규 사용자',height:240,valueFmt:v=>fmtInt(v)+'명'});
}
