import { lineChart, sparkline } from './charts.js';
import { fmtInt, fmtPct, fmtMoney, fmtDur, fmtMD, fmtLong, todayKst, esc, sum, avg, deltaInfo } from './format.js';
import { EVENT_META, eventMeta, localizeName, COLORS } from './labels.js';

export const SECTIONS = [['overview', '운영 요약'], ['growth', '유입·성장'], ['quality', '상세 진단']];
const number = (v, unit = '') => v == null ? '—' : fmtInt(v) + unit;
const tag = (label, tone = '') => '<span class="status-tag ' + tone + '">' + esc(label) + '</span>';
const card = (title, sub, body, cls = 'span-12') => '<section class="card ' + cls + '"><div class="card-h"><div><h2>' + title + '</h2><p>' + sub + '</p></div></div>' + body + '</section>';
const empty = (text) => '<div class="empty-state">' + esc(text) + '</div>';
export function periodData(docs, view) {
  return Object.values(docs.operations?.byRange ?? {}).find((v) => v.from === view.dates[0] && v.to === view.dates.at(-1)) ?? null;
}
export function eventData(docs, view, name) {
  const selected = Object.values(docs.summary.eventsByRange ?? {}).find((v) => v.from === view.dates[0] && v.to === view.dates.at(-1));
  const row = selected?.events?.find((v) => v.name === name);
  const values = docs.events.series?.[name];
  return { count: values ? sum(values.slice(view.from)) : (row?.count ?? (selected ? 0 : null)), users: selected ? (row?.users ?? 0) : null,
    observed: !!row || !!values, values: values ? values.slice(view.from) : [] };
}
function change(current, previous) {
  if (current == null || previous == null) return tag('비교 자료 없음');
  const d = deltaInfo(current, previous);
  if (d.dir === 'new') return tag('직전 기간 관측 없음');
  if (d.pct == null) return tag('변화 없음');
  return tag((d.pct >= 0 ? '+' : '') + (d.pct * 100).toFixed(1) + '%', d.pct > 0 ? 'positive' : d.pct < 0 ? 'warning' : '');
}
function metric(label, value, note, detail = '', trend = '') {
  return '<article class="kpi"><div class="lab">' + esc(label) + '</div><div class="val">' + value + '</div><div class="kfoot"><div>' + detail + '<div class="note">' + note + '</div></div>' + trend + '</div></article>';
}
export function businessKpis(docs, view) {
  const period = periodData(docs, view); const current = period?.current; const previous = period?.previous;
  const retained = docs.summary.cohort;
  return '<section class="kpis span-12" aria-label="운영 핵심 지표">' +
    metric('기간 활성 사용자', number(current?.activeUsers, '명'), view.len + '일 내 중복 제거', change(current?.activeUsers, previous?.activeUsers), sparkline(view.cur('dau'), COLORS.dau)) +
    metric('신규 사용자', number(current?.newUsers, '명'), 'GA4 신규 사용자 · 스토어 설치 수와 다름', change(current?.newUsers, previous?.newUsers), sparkline(view.cur('newUsers'), COLORS.install)) +
    metric('7일 재방문율', retained?.days?.[7] == null ? '—' : fmtPct(retained.days[7], 1), retained ? '첫 세션 코호트 ' + fmtInt(retained.size) + '명 · 별도 기준 기간' : '코호트 자료 없음', retained && retained.size < 30 ? tag('작은 표본', 'warning') : '') +
    metric('28일 활성 사용자', number(view.last('mau'), '명'), '기준일 직전 28일 · MAU', '', sparkline(view.cur('mau'), COLORS.mau)) + '</section>';
}
export function dailyView(docs, yesterday = new Date(Date.parse(todayKst()) - 86400000).toISOString().slice(0, 10), range = 30) {
  const days = [7, 30, 100, 365].includes(Number(range)) ? Number(range) : 30;
  const cutoff = new Date(Date.parse(yesterday) - (days - 1) * 86400000).toISOString().slice(0, 10);
  const indices = docs.series.dates.flatMap((date, i) => date >= cutoff && date <= yesterday ? [i] : []);
  const yesterdayIndex = docs.series.dates.indexOf(yesterday);
  return { yesterday, range: days, dates: indices.map((i) => docs.series.dates[i]),
    cur: (key) => indices.map((i) => docs.series[key]?.[i]),
    yesterdayValue: (key) => yesterdayIndex < 0 ? null : docs.series[key]?.[yesterdayIndex] ?? null };
}
export function dailySelection(view, date) {
  const index = view.dates.indexOf(date);
  return { label: date === view.yesterday ? '어제 DAU' : '선택일 DAU', date: fmtLong(date),
    value: number(index < 0 ? null : view.cur('dau')[index], '명') };
}
export function dailyReadout(view, date) {
  const index = view.dates.indexOf(date);
  if (index < 0) return fmtLong(date) + ' · 아직 집계되지 않았습니다.';
  return fmtLong(date) + ' · DAU ' + number(view.cur('dau')[index], '명') + ' · MAU ' + number(view.cur('mau')[index], '명') + ' (해당일 기준 직전 28일)';
}
export function weekdayDauAverages(docs, range, yesterday) {
  const days = [7, 30, 100, 365].includes(Number(range)) ? Number(range) : 30;
  const cutoff = new Date(Date.parse(yesterday) - (days - 1) * 86400000).toISOString().slice(0, 10);
  const buckets = ['월', '화', '수', '목', '금', '토', '일'].map((label) => ({ label, total: 0, count: 0 }));
  for (const [i, date] of docs.series.dates.entries()) {
    const value = docs.series.dau?.[i];
    if (date < cutoff || date > yesterday || typeof value !== 'number' || !Number.isFinite(value) || value < 0) continue;
    const weekday = (new Date(date + 'T00:00:00Z').getUTCDay() + 6) % 7;
    buckets[weekday].total += value;
    buckets[weekday].count++;
  }
  return buckets.map(({ label, total, count }) => ({ label, count, average: count ? total / count : null }));
}
function weekdayDauCard(docs, ui, yesterday) {
  const range = [7, 30, 100, 365].includes(Number(ui.range)) ? Number(ui.range) : 30;
  const rows = weekdayDauAverages(docs, range, yesterday);
  const max = Math.max(0, ...rows.map((row) => row.average ?? 0));
  return '<div class="weekday-dau" aria-label="DAU 요일별 평균"><div class="daily-chart-head"><h2>요일별 평균 DAU</h2><span class="sub">어제까지 최근 ' + range + '일 · 한국 시간</span></div><div class="weekday-dau-grid">' + rows.map((row) => '<article><span>' + row.label + '요일</span><b>' + (row.average == null ? '—' : row.average.toLocaleString('ko-KR', { minimumFractionDigits: 1, maximumFractionDigits: 1 }) + '<small>명</small>') + '</b><div class="weekday-dau-track" aria-hidden="true"><i style="width:' + (max ? (row.average ?? 0) / max * 100 : 0) + '%"></i></div><small>' + (row.count ? row.count + '일 평균' : '집계 없음') + '</small></article>').join('') + '</div><p class="sub">집계된 날짜만 평균에 포함합니다. DAU 0명인 날은 포함하고, 미집계 날짜는 제외합니다.</p></div>';
}
export function dailyOverviewCard(docs, view, ui) {
  const selected = view.dates.includes(ui.dailyDate) ? ui.dailyDate : view.yesterday;
  const hero = dailySelection(view, selected);
  const waiting = view.yesterdayValue('dau') == null;
  return '<section class="card span-12 daily-overview"><div class="card-h"><div><h1>일간 활성 사용자 · DAU</h1><p>출시 앱 · 하루 동안 앱을 쓴 사용자</p></div></div><div class="daily-kpis">' +
    '<article class="daily-dau" aria-live="polite"><span id="daily-dau-label">' + hero.label + '</span><strong id="daily-dau-date">' + esc(hero.date) + '</strong><b id="daily-dau-value">' + hero.value + '</b><small>날짜를 선택하면 해당일 DAU를 확인할 수 있습니다.</small></article>' +
    '<article class="daily-mau"><span>MAU · 직전 28일</span><b>' + number(view.yesterdayValue('mau'), '명') + '</b><small>어제 ' + esc(fmtLong(view.yesterday)) + ' 기준</small></article></div>' +
    (waiting ? '<p class="notice">어제 자료는 아직 집계되지 않았습니다. 아래 차트는 최근 ' + view.range + '일 중 집계된 날짜만 보여줍니다.</p>' : '') +
    '<div class="daily-chart-head"><h2>최근 ' + view.range + '일 DAU 추이</h2><span class="sub">차트의 날짜를 눌러 확인</span></div>' +
    '<div class="daily-legend"><button class="chip" data-action="legend" data-key="dau" aria-pressed="' + ui.visible.dau + '"><i style="background:' + COLORS.dau + '"></i>DAU 일간</button><button class="chip" data-action="legend" data-key="mau" aria-pressed="' + ui.visible.mau + '"><i style="background:' + COLORS.mau + '"></i>MAU 직전 28일</button></div>' +
    (view.dates.length ? '<div id="ch-users" style="min-height:240px"></div>' : empty('최근 ' + view.range + '일의 집계 자료가 아직 없습니다.')) +
    '<details class="growth-help"><summary>요일별 평균 보기</summary>' + weekdayDauCard(docs, ui, view.yesterday) + '</details>' +
    '<p id="daily-readout" class="daily-readout" aria-live="polite">' + esc(dailyReadout(view, selected)) + '</p></section>';
}

// 사용자 행동은 공통 이벤트 정의에서 가져와 표시 목록의 수동 누락을 방지한다.
// 자동 작업 및 OS/예약 진단은 기능 사용 순위에서 제외한다.
const FEATURES = Object.entries(EVENT_META)
  .filter(([name, meta]) => !meta.retired && meta.group !== 'system' &&
    !/^(ops_|alarm_schedule_|alarm_refresh_|device_boot_)/.test(name) &&
    !['alarm_fired', 'auto_backup_created'].includes(name))
  .map(([name, meta]) => [name, meta.label]);
export function adoptionCard(docs, view, limit = Infinity) {
  const ranked = FEATURES.map(([name, label], order) => ({ name, label, order, data: eventData(docs, view, name) }))
    .sort((a, b) => (b.data.count ?? -1) - (a.data.count ?? -1) || Number(b.data.observed) - Number(a.data.observed) || a.order - b.order);
  const max = ranked[0]?.data.count ?? 0;
  const rows = ranked.slice(0, limit).map(({ name, label, data }, index) => {
    const color = index < 5 && data.count > 0 ? COLORS.palette[index] : 'var(--muted)';
    const marker = '<span class="feature-rank" style="color:' + color + '">' + (index + 1) + '</span><i class="feature-dot" style="background:' + color + '"></i>';
    const usage = data.observed ? '<div class="feature-usage"><b>' + number(data.count, '회') + '</b><div class="feature-track"><i style="background:' + color + ';width:' + (max > 0 ? data.count / max * 100 : 0) + '%"></i></div></div>' : '—';
    return '<tr data-action="event" data-event="' + name + '" tabindex="0" role="button" aria-label="' + label + ' 상세"><th><span class="feature-label">' + marker + label + '</span></th><td>' + (data.observed ? number(data.users, '명') : tag('미관측')) + '</td><td>' + usage + '</td></tr>';
  }).join('');
  return card('핵심 기능 활용', '선택 기간 이용 횟수 내림차순 · 상위 5개 기능 색상 표시', '<div class="table-scroll"><table class="ops-table feature-table"><thead><tr><th>기능</th><th>사용자 수</th><th>이용 횟수</th></tr></thead><tbody>' + rows + '</tbody></table></div><p class="sub">사용자 수는 선택 기간의 중복 제거 인원입니다. 미관측은 미사용·구버전·수집 누락을 구분할 자료가 아직 없다는 뜻입니다.</p>');
}
const countryGroupKey = country => !country || country === '(missing)' || country === '(not set)' ? '(not set)' : country;
export const COUNTRY_FEATURES = [
  ['onboarding_complete','시작 완료'],['team_roster_created','전체조 생성'],['alarm_template_saved','고정 알람 저장'],
  ['ot_saved','OT·특근 기록'],['work_hours_settings_saved','근무시간 설정'],['calendar_theme_changed','테마 변경'],
  ['shift_assigned','근무 지정·변경'],['memo_saved','메모 저장'],['shift_name_changed','근무명 변경'],
];
export function groupedCountryRows(period, sort = 'activeUsers') {
  const metric = sort === 'newUsers' ? 'newUsers' : 'activeUsers';
  const totals = new Map();
  for(const row of period?.countries ?? []) {
    const key=countryGroupKey(row.name);
    // Before a union refresh arrives, keep conservative legacy ranking; never claim summed distinct users.
    totals.set(key,Math.max(totals.get(key) ?? 0,row[metric] ?? 0));
  }
  const groups = new Map();
  for (const row of period?.countryLanguages ?? []) {
    const key=countryGroupKey(row.country);
    if(!groups.has(key)) groups.set(key, []);
    groups.get(key).push(row);
  }
  const score = (country, rows) => totals.get(country) ?? Math.max(0, ...rows.map(row => row[metric] ?? 0));
  return [...groups].sort((a,b) => score(b[0],b[1]) - score(a[0],a[1]) || a[0].localeCompare(b[0]))
    .flatMap(([,rows]) => [...rows].sort((a,b) => b[metric] - a[metric] || a.language.localeCompare(b.language)));
}
const marketLabel = row => localizeName('country', countryGroupKey(row.country)) + ' / ' + localizeName('language', row.language);
export function countryCard(docs, view, ui) {
  const period = periodData(docs, view); const rows = period?.countryLanguages;
  if (!rows) return card('국가별 성장과 기능 활용', '국가 안에서 사용된 언어까지 함께 확인', empty('국가·언어 교차 집계가 아직 연결되지 않았습니다. 다음 집계부터 표시됩니다.'));
  const previous = new Map((period.previousCountryLanguages ?? []).map(r => [r.name,r]));
  const sorted = groupedCountryRows(period, ui.marketSort);
  const selected = sorted.some(r=>r.name===ui.country) ? ui.country : sorted[0]?.name;
  const chosen = sorted.find(r=>r.name===selected);
  const sizes=new Map(); for(const row of sorted){const key=countryGroupKey(row.country);sizes.set(key,(sizes.get(key) ?? 0)+1);}
  const metric = (r,name) => r.events == null ? '—' : number(r.events[name]?.users ?? null,'명');
  const html = sorted.map((r,i) => {
    const group=countryGroupKey(r.country);const first=i===0 || countryGroupKey(sorted[i-1].country)!==group;
    const country=first ? '<th scope="rowgroup" rowspan="'+sizes.get(group)+'">'+esc(localizeName('country',group))+'</th>' : '';
    return '<tr class="'+(first?'country-group-start ':'')+(selected===r.name?'selected':'')+'" data-action="country" data-key="'+esc(r.name)+'" tabindex="0" role="button" aria-label="'+esc(marketLabel(r))+' 추이">'+country+'<td>'+esc(localizeName('language',r.language))+'</td><td>'+number(r.activeUsers)+'</td><td>'+change(r.activeUsers,previous.get(r.name)?.activeUsers)+'</td><td>'+number(r.newUsers)+'</td>'+COUNTRY_FEATURES.map(([name])=>'<td>'+metric(r,name)+'</td>').join('')+'</tr>';
  }).join('');
  return card('국가별 성장과 기능 활용', '국가 전체 규모 순 · 국가 안에서 언어별 표시 · 같은 '+view.len+'일 기준 사용자 수', '<div class="tabs" role="group" aria-label="국가 정렬"><button class="tab" data-action="market-sort" data-key="activeUsers" aria-pressed="'+(ui.marketSort!=='newUsers')+'">활성 사용자 순</button><button class="tab" data-action="market-sort" data-key="newUsers" aria-pressed="'+(ui.marketSort==='newUsers')+'">신규 사용자 순</button></div><div class="table-scroll"><table class="ops-table market-table"><thead><tr><th>국가</th><th>언어</th><th>활성</th><th>직전 대비</th><th>신규 사용자</th>'+COUNTRY_FEATURES.map(([,label])=>'<th>'+label+'</th>').join('')+'</tr></thead><tbody>'+html+'</tbody></table></div><div class="market-chart-head"><b>'+esc(chosen?marketLabel(chosen):'국가·언어 선택')+' · 일간 활성 추이</b><span class="sub">최근 최대 100일 · 행을 눌러 국가·언어 선택</span></div><div id="ch-country" style="min-height:200px"></div><p class="sub">신규 사용자는 GA4 신규 사용자이며 스토어 신규 설치 수와 다릅니다. 시작 완료는 온보딩 완료입니다. 언어는 GA4 기기 언어 기준이며 앱 표시 언어와 다를 수 있습니다. 국가·언어가 바뀐 사용자는 여러 조합에 포함될 수 있어 합계는 전체 이용자 수와 다를 수 있습니다. 고정 알람 저장은 온보딩 기본 알람을 제외한 고정 알람 생성·수정 저장, 테마 변경은 달력 테마 변경 기준입니다. 근무시간 설정은 계측이 포함된 앱 버전부터 집계됩니다. 표는 좌우로 밀어 모든 지표를 확인할 수 있습니다.</p>');
}
const HEALTH_EVENTS = [['alarm_schedule_ok', '예약 API 완료'], ['alarm_schedule_failed', '예약 API 실패'], ['alarm_fired', '실제 수신·울림 진입'], ['device_boot_seen', '부팅 신호 관측'], ['alarm_refresh_completed', '재등록 갱신 완료'], ['alarm_refresh_failed', '재등록 갱신 실패']];
export function reliabilityCard(docs, view) {
  const tiles = HEALTH_EVENTS.map(([name, title]) => { const data = eventData(docs, view, name); return '<article class="health-stat"><span>' + title + '</span><b>' + (data.observed ? number(data.count, '회') : '—') + '</b>' + (!data.observed ? tag('미관측') : '') + '</article>'; }).join('');
  const dismissed = eventData(docs, view, 'alarm_dismissed'); const snoozed = eventData(docs, view, 'alarm_snoozed'); const timeout = eventData(docs, view, 'alarm_no_response');
  return card('알람 신뢰도 · 관측된 사실', '예약과 실제 울림, 종료 행동을 서로 다른 단계로 봅니다.', '<div class="health-grid">' + tiles + '</div><div class="outcome-strip"><span>끄기 <b>' + number(dismissed.count, '회') + '</b></span><span>연장 <b>' + number(snoozed.count, '회') + '</b></span><span>무응답 종료 <b>' + number(timeout.count, '회') + '</b></span></div><div class="notice"><div><b>예약 완료를 울림 성공률로 계산하지 않습니다.</b><br>재시도·반복 예약이 포함됩니다. 알람 이벤트는 다음 앱 실행 때 보고되므로 서로 같은 알람의 전환 분모가 아닙니다. 무응답도 미울림을 입증하지 않습니다.</div></div>');
}
export function manufacturerCard(docs, view) {
  const period = periodData(docs, view); const rows = period?.manufacturers;
  const event = (r, name, field = 'count') => r.events == null ? null : (r.events[name]?.[field] ?? null);
  const html = (rows ?? []).map((r) => '<tr><th>' + esc(r.name === 'Google' ? 'Google (Pixel)' : localizeName('manufacturer', r.name)) + '</th><td>' + number(r.activeUsers) + '</td><td>' + number(event(r, 'alarm_schedule_failed')) + '</td><td>' + number(event(r, 'alarm_fired')) + '</td><td>' + number(event(r, 'alarm_refresh_failed')) + '</td><td>' + number(event(r, 'ops_battery_restricted', 'users')) + '</td><td>' + number(event(r, 'ops_exact_denied', 'users')) + '</td></tr>').join('');
  return card('제조사별 알람·제한 상태', 'GA4 기기 브랜드 기준 · 선택 기간 내 관측 · 실패율 비교에는 표본과 재시도를 함께 확인', rows ? '<div class="table-scroll"><table class="ops-table"><thead><tr><th>제조사</th><th>활성 사용자</th><th>예약 실패</th><th>울림 진입</th><th>갱신 실패</th><th>배터리 제한 사용자</th><th>정확 알람 거부 사용자</th></tr></thead><tbody>' + html + '</tbody></table></div>' : empty('제조사별 운영 집계가 아직 연결되지 않았습니다.'));
}
export function permissionCard(docs, view) {
  const states = [['ops_daily_ready', '권한 허용 상태'], ['ops_daily_restricted', '미허용 권한 있음'], ['ops_daily_unknown', '권한 확인 불가'], ['ops_battery_restricted', '배터리 최적화 적용'], ['ops_exact_denied', '정확 알람 미허용'], ['ops_notification_blocked', '앱 알림 차단'], ['ops_channel_blocked', '알람 채널 차단'], ['ops_fullscreen_denied', '전체화면 미허용']];
  const rows = states.map(([name, title]) => { const data = eventData(docs, view, name); return '<tr><th>' + title + '</th><td>' + (data.observed ? number(data.users, '명') : tag('미관측')) + '</td></tr>'; }).join('');
  return card('권한·배터리 상태의 도달 범위', '앱 실행 시 기기 날짜별 하루 1회 OS 상태 관측 · 선택 기간의 중복 제거 사용자', '<div class="table-scroll"><table class="ops-table"><thead><tr><th>관측 상태</th><th>사용자</th></tr></thead><tbody>' + rows + '</tbody></table></div><p class="sub">기간 중 권한이 바뀐 사용자는 여러 상태에 포함됩니다. 따라서 합계나 허용률로 계산하지 않습니다. 미관측은 새 계측이 아직 보고되지 않았다는 뜻이며, 확인 불가와 미허용은 별도 상태입니다.</p>');
}

export function collectionCard(docs, view) {
  const p = periodData(docs, view); const reports = { ...(docs.summary.coverage ?? {}), ...(p?.coverage ?? {}) };
  const names = { core: '활성·신규·세션', ads: '광고 수익', cohort: '재방문 코호트', eventsDaily: '일별 행동', current: '기간 이용자', countries: '국가 운영 지표', countryEvents: '국가별 기능', manufacturers: '제조사 운영 지표', manufacturerEvents: '제조사별 알람', countryDaily: '국가 일별 추이', countryLanguages: '국가·언어 운영 지표', countryLanguageEvents: '국가·언어별 기능', countryLanguageDaily: '국가·언어 일별 추이' };
  const statuses = Object.entries(names).map(([key, title]) => { const data = reports[key] ?? docs.operations?.coverage?.[key]; const limited = data?.thresholded || data?.sampled || data?.otherRowLoss || data?.truncated; const label = !data || data.status === 'unavailable' ? '미연결/조회 실패' : data.status === 'empty' ? '조회 성공 · 자료 없음' : limited ? '집계 제한 있음' : '집계 완료'; return '<li><span>' + title + '</span>' + tag(label, !data || data.status === 'unavailable' || limited ? 'warning' : '') + '</li>'; }).join('');
  return card('데이터 수집 상태와 판단 범위', '미연결을 0으로 표시하지 않고, 관측 범위를 함께 확인합니다.', '<div class="coverage-grid"><ul class="coverage-list">' + statuses + '</ul><div class="coverage-notes"><h3>운영자가 알아야 할 한계</h3><p>전체교대조 및 새 운영 이벤트: 다음 계측 앱 출시 후 수집. 과거 데이터 소급 복원 불가.</p><p>알람 진단: 앱 재개 후 전송, 최근 72시간·종류별 회당 40건·로컬 기록 최대 1,000건 상한, 첫 실행은 기존 기록을 제외하는 기준선만 저장.</p><p>배터리 제한: 하루 1회 OS 상태 관측이며 알람 실패 원인이 확인된 오류는 아닙니다.</p><p>강제종료 후 동작·실제 미울림·Crashlytics 오류율: 현재 직접 판정할 수집 근거가 없습니다. 성공으로 표시하지 않습니다.</p><p>한국 시간 12:17을 포함해 3시간마다 재집계. 새로고침은 저장된 집계를 읽으며 서버 집계를 다시 실행하지 않습니다.</p></div></div>');
}
export function revenueCard(docs, view) {
  const data = docs.summary.coverage?.ads; const available = data?.status === 'available' || data?.status === 'empty';
  const revenue = available ? sum(view.cur('adRevenue')) : null; const impressions = sum(view.cur('adImpressions'));
  const current = periodData(docs, view)?.current;
  return card('수익과 사용 가치', '실제 집계된 광고 수익만 사용 · 매출/원가의 전체 사업 손익과 다릅니다.', '<div class="stats"><div class="stat"><b>' + (revenue == null ? '—' : fmtMoney(revenue, docs.summary.currency ?? 'USD')) + '</b><span>기간 광고 수익</span></div><div class="stat"><b>' + (revenue == null || impressions <= 0 ? '—' : fmtMoney(revenue / impressions * 1000, docs.summary.currency ?? 'USD')) + '</b><span>광고 1,000회당 수익</span></div><div class="stat"><b>' + number(impressions) + '</b><span>광고 노출</span></div><div class="stat"><b>' + (current?.activeUsers > 0 ? fmtDur(current.engagementSec / current.activeUsers) : '—') + '</b><span>기간 활성 사용자당 참여시간</span></div></div><p class="sub">광고 수익 미연결은 수익 0원이 아닙니다. 광고 비용·서버비·결제 매출은 연결되지 않아 순이익이나 국가별 ROI를 계산하지 않습니다.</p>');
}
export function mountCountryChart(root, docs, view, ui) {
  const host = root.querySelector('#ch-country'); if (!host) return null;
  const trend = docs.operations?.countryLanguageTrend;
  const rows = groupedCountryRows(periodData(docs,view), ui.marketSort);
  const selected = rows.find(r=>r.name===ui.country) ?? rows[0];
  const item = trend?.series?.[selected?.name];
  if (!item) {host.innerHTML=empty('선택 국가·언어의 일별 추이가 아직 없습니다.');return null;}
  const first = trend.dates.findIndex(d=>d>=view.dates[0]); const start=first<0?trend.dates.length:first;
  const label = marketLabel(selected);
  return lineChart(host,{dates:trend.dates.slice(start),title:label+' 일간 활성 사용자',height:210,
    series:[{key:'countryLanguage',label,color:COLORS.dau,values:item.dau.slice(start),area:true}],valueFmt:v=>fmtInt(v)+'명'});
}
