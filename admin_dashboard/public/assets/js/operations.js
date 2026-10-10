import { lineChart, sparkline } from './charts.js';
import { fmtInt, fmtPct, fmtMoney, fmtDur, fmtMD, fmtLong, todayKst, esc, sum, avg, deltaInfo } from './format.js';
import { eventMeta, localizeName, COLORS } from './labels.js';

export const SECTIONS = [['overview', '운영 요약'], ['growth', '성장·국가'], ['product', '기능 활용'], ['quality', '알람·기기']];
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
  return { count: values ? sum(values.slice(view.from)) : (selected ? 0 : null), users: selected ? (row?.users ?? 0) : null,
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
export function dailyView(docs, yesterday = new Date(Date.parse(todayKst()) - 86400000).toISOString().slice(0, 10)) {
  const cutoff = new Date(Date.parse(yesterday) - 9 * 86400000).toISOString().slice(0, 10);
  const indices = docs.series.dates.flatMap((date, i) => date >= cutoff && date <= yesterday ? [i] : []);
  const yesterdayIndex = docs.series.dates.indexOf(yesterday);
  return { yesterday, dates: indices.map((i) => docs.series.dates[i]),
    cur: (key) => indices.map((i) => docs.series[key]?.[i]),
    yesterdayValue: (key) => yesterdayIndex < 0 ? null : docs.series[key]?.[yesterdayIndex] ?? null };
}
export function dailyReadout(view, date) {
  const index = view.dates.indexOf(date);
  if (index < 0) return '선택할 날짜의 자료가 아직 없습니다.';
  return fmtLong(date) + ' · DAU ' + number(view.cur('dau')[index], '명') + ' · MAU ' + number(view.cur('mau')[index], '명');
}
export function dailyOverviewCard(docs, view, ui) {
  const selected = view.dates.includes(ui.dailyDate) ? ui.dailyDate : view.dates.at(-1);
  const waiting = view.yesterdayValue('dau') == null;
  const buttons = view.dates.map((date) => '<button class="chip" data-action="daily-day" data-date="' + date + '" aria-label="' + esc(fmtLong(date)) + ' DAU MAU 확인" aria-pressed="' + (date === selected) + '">' + fmtMD(date) + '</button>').join('');
  return '<section class="card span-12 daily-overview"><div class="card-h"><div><h1>DAU · MAU</h1><p>어제 ' + esc(fmtLong(view.yesterday)) + ' 기준 · 출시 앱</p></div></div><div class="daily-kpis">' +
    '<article><span>어제 DAU</span><b>' + number(view.yesterdayValue('dau'), '명') + '</b><small>하루 동안 앱을 쓴 사용자</small></article>' +
    '<article><span>어제 기준 MAU</span><b>' + number(view.yesterdayValue('mau'), '명') + '</b><small>직전 28일 동안 앱을 쓴 사용자</small></article></div>' +
    (waiting ? '<p class="notice">어제 자료는 아직 집계되지 않았습니다. 아래 차트는 최근 10일 중 집계된 날짜만 보여줍니다.</p>' : '') +
    '<div class="daily-chart-head"><h2>최근 10일 추이</h2><span class="sub">차트나 날짜를 눌러 하루씩 확인</span></div>' +
    '<div class="daily-legend"><button class="chip" data-action="legend" data-key="dau" aria-pressed="' + ui.visible.dau + '"><i style="background:' + COLORS.dau + '"></i>DAU 일간</button><button class="chip" data-action="legend" data-key="mau" aria-pressed="' + ui.visible.mau + '"><i style="background:' + COLORS.mau + '"></i>MAU 월간</button></div>' +
    (view.dates.length ? '<div id="ch-users" style="min-height:240px"></div><div class="daily-days" aria-label="일별 사용자 확인">' + buttons + '</div>' : empty('최근 10일의 집계 자료가 아직 없습니다.')) +
    '<p id="daily-readout" class="daily-readout" aria-live="polite">' + esc(dailyReadout(view, selected)) + '</p></section>';
}

const FEATURES = [
  ['onboarding_complete', '시작 완료'], ['team_roster_created', '전체교대조 생성'], ['all_shifts_opened', '전체근무표 열람'],
  ['shift_assigned', '근무 변경'], ['alarm_template_saved', '알람 설정'], ['alarm_dismissed', '알람 끄기'],
  ['memo_saved', '메모'], ['ot_saved', 'OT·특근'], ['sleep_record_saved', '수면 기록'], ['friend_share_started', '친구 공유 시작'],
  ['backup_created', '직접 백업'], ['help_opened', '도움말'],
];
export function adoptionCard(docs, view) {
  const totalUsers = periodData(docs, view)?.current?.totalUsers;
  const ranked = FEATURES.map(([name, label], order) => ({ name, label, order, data: eventData(docs, view, name) }))
    .sort((a, b) => Number(b.data.observed) - Number(a.data.observed) || (b.data.count ?? -1) - (a.data.count ?? -1) || a.order - b.order);
  const rows = ranked.map(({ name, label, data }) => {
    const share = data.observed && data.users != null && totalUsers > 0 && data.users <= totalUsers ? data.users / totalUsers : null;
    return '<tr data-action="event" data-event="' + name + '" tabindex="0" role="button" aria-label="' + label + ' 상세"><th>' + label + '</th><td>' + (data.observed ? number(data.users, '명') : tag('미관측')) + '</td><td>' + (share == null ? '—' : '<div class="adoption"><i style="width:' + (share * 100) + '%"></i><span>' + fmtPct(share, 1) + '</span></div>') + '</td><td>' + (data.observed ? number(data.count, '회') : '—') + '</td></tr>';
  }).join('');
  return card('핵심 기능의 도달과 활용', '선택 기간 이용 횟수 내림차순 · 기능별 사용자 수와 도달률 · 미관측은 맨 아래', '<div class="table-scroll"><table class="ops-table"><thead><tr><th>기능</th><th>사용자</th><th>기간 이용자 대비</th><th>이용 횟수</th></tr></thead><tbody>' + rows + '</tbody></table></div><p class="sub">기능 사용률의 분모는 같은 기간의 전체 이용자(totalUsers)입니다. 미관측은 미사용·구버전·수집 누락을 구분할 자료가 아직 없다는 뜻입니다.</p>');
}
export function countryCard(docs, view, ui) {
  const period = periodData(docs, view); const rows = period?.countries;
  if (!rows) return card('국가별 성장과 기능 활용', '언어 설정이 아닌 GA4의 실제 활동 국가 기준', empty('국가 운영 집계가 아직 연결되지 않았습니다. 전체 분포와 별도로 다음 집계부터 표시됩니다.'));
  const previous = new Map((period.previousCountries ?? []).map((r) => [r.name, r]));
  const sorted = [...rows].sort((a, b) => ui.marketSort === 'newUsers' ? b.newUsers - a.newUsers : b.activeUsers - a.activeUsers);
  const selected = ui.country ?? sorted[0]?.name;
  const metric = (r, name) => r.events == null ? '—' : number(r.events[name]?.users ?? null, '명');
  const html = sorted.map((r) => '<tr class="' + (selected === r.name ? 'selected' : '') + '" data-action="country" data-key="' + esc(r.name) + '" tabindex="0" role="button" aria-label="' + esc(localizeName('country', r.name)) + ' 추이"><th>' + esc(localizeName('country', r.name)) + '</th><td>' + number(r.activeUsers) + '</td><td>' + change(r.activeUsers, previous.get(r.name)?.activeUsers) + '</td><td>' + number(r.newUsers) + '</td><td>' + metric(r, 'onboarding_complete') + '</td><td>' + metric(r, 'team_roster_created') + '</td><td>' + metric(r, 'alarm_dismissed') + '</td></tr>').join('');
  return card('국가별 성장과 기능 활용', '같은 ' + view.len + '일 기준 · 활성/신규/핵심 기능의 사용자 수', '<div class="tabs" role="group" aria-label="국가 정렬"><button class="tab" data-action="market-sort" data-key="activeUsers" aria-pressed="' + (ui.marketSort !== 'newUsers') + '">활성 사용자 순</button><button class="tab" data-action="market-sort" data-key="newUsers" aria-pressed="' + (ui.marketSort === 'newUsers') + '">신규 사용자 순</button></div><div class="table-scroll"><table class="ops-table market-table"><thead><tr><th>국가</th><th>활성</th><th>직전 대비</th><th>신규</th><th>시작 완료</th><th>전체조 생성</th><th>알람 끄기</th></tr></thead><tbody>' + html + '</tbody></table></div><div class="market-chart-head"><b>' + esc(localizeName('country', selected ?? '국가 선택')) + ' · 일간 활성 추이</b><span class="sub">최근 최대 100일 · 행을 눌러 국가 선택</span></div><div id="ch-country" style="min-height:200px"></div><p class="sub">국가를 이동한 사용자는 여러 국가에 포함될 수 있어 국가별 합계는 전체 이용자 수와 다를 수 있습니다. 신규·시작 완료는 동일 사용자의 전환율을 뜻하지 않습니다.</p>');
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
  const html = (rows ?? []).map((r) => '<tr><th>' + esc(r.name === 'Google' ? 'Google (Pixel)' : r.name === '(not set)' ? '확인 불가' : r.name) + '</th><td>' + number(r.activeUsers) + '</td><td>' + number(event(r, 'alarm_schedule_failed')) + '</td><td>' + number(event(r, 'alarm_fired')) + '</td><td>' + number(event(r, 'alarm_refresh_failed')) + '</td><td>' + number(event(r, 'ops_battery_restricted', 'users')) + '</td><td>' + number(event(r, 'ops_exact_denied', 'users')) + '</td></tr>').join('');
  return card('제조사별 알람·제한 상태', 'GA4 기기 브랜드 기준 · 선택 기간 내 관측 · 실패율 비교에는 표본과 재시도를 함께 확인', rows ? '<div class="table-scroll"><table class="ops-table"><thead><tr><th>제조사</th><th>활성 사용자</th><th>예약 실패</th><th>울림 진입</th><th>갱신 실패</th><th>배터리 제한 사용자</th><th>정확 알람 거부 사용자</th></tr></thead><tbody>' + html + '</tbody></table></div>' : empty('제조사별 운영 집계가 아직 연결되지 않았습니다.'));
}
export function permissionCard(docs, view) {
  const states = [['ops_daily_ready', '권한 허용 상태'], ['ops_daily_restricted', '미허용 권한 있음'], ['ops_daily_unknown', '권한 확인 불가'], ['ops_battery_restricted', '배터리 최적화 적용'], ['ops_exact_denied', '정확 알람 미허용'], ['ops_notification_blocked', '앱 알림 차단'], ['ops_channel_blocked', '알람 채널 차단'], ['ops_fullscreen_denied', '전체화면 미허용']];
  const rows = states.map(([name, title]) => { const data = eventData(docs, view, name); return '<tr><th>' + title + '</th><td>' + (data.observed ? number(data.users, '명') : tag('미관측')) + '</td></tr>'; }).join('');
  return card('권한·배터리 상태의 도달 범위', '앱 실행 시 기기 날짜별 하루 1회 OS 상태 관측 · 선택 기간의 중복 제거 사용자', '<div class="table-scroll"><table class="ops-table"><thead><tr><th>관측 상태</th><th>사용자</th></tr></thead><tbody>' + rows + '</tbody></table></div><p class="sub">기간 중 권한이 바뀐 사용자는 여러 상태에 포함됩니다. 따라서 합계나 허용률로 계산하지 않습니다. 미관측은 새 계측이 아직 보고되지 않았다는 뜻이며, 확인 불가와 미허용은 별도 상태입니다.</p>');
}

export function collectionCard(docs, view) {
  const p = periodData(docs, view); const reports = { ...(docs.summary.coverage ?? {}), ...(p?.coverage ?? {}) };
  const names = { core: '활성·신규·세션', ads: '광고 수익', cohort: '재방문 코호트', eventsDaily: '일별 행동', current: '기간 이용자', countries: '국가 운영 지표', countryEvents: '국가별 기능', manufacturers: '제조사 운영 지표', manufacturerEvents: '제조사별 알람', countryDaily: '국가 일별 추이' };
  const statuses = Object.entries(names).map(([key, title]) => { const data = reports[key] ?? docs.operations?.coverage?.[key]; const limited = data?.thresholded || data?.sampled || data?.otherRowLoss || data?.truncated; const label = !data || data.status === 'unavailable' ? '미연결/조회 실패' : data.status === 'empty' ? '조회 성공 · 자료 없음' : limited ? '집계 제한 있음' : '집계 완료'; return '<li><span>' + title + '</span>' + tag(label, !data || data.status === 'unavailable' || limited ? 'warning' : '') + '</li>'; }).join('');
  return card('데이터 수집 상태와 판단 범위', '미연결을 0으로 표시하지 않고, 관측 범위를 함께 확인합니다.', '<div class="coverage-grid"><ul class="coverage-list">' + statuses + '</ul><div class="coverage-notes"><h3>운영자가 알아야 할 한계</h3><p>전체교대조 및 새 운영 이벤트: 다음 계측 앱 출시 후 수집. 과거 데이터 소급 복원 불가.</p><p>알람 진단: 앱 재개 후 전송, 최근 72시간·종류별 회당 40건·로컬 기록 최대 1,000건 상한, 첫 실행은 기존 기록을 제외하는 기준선만 저장.</p><p>배터리 제한: 하루 1회 OS 상태 관측이며 알람 실패 원인이 확인된 오류는 아닙니다.</p><p>강제종료 후 동작·실제 미울림·Crashlytics 오류율: 현재 직접 판정할 수집 근거가 없습니다. 성공으로 표시하지 않습니다.</p><p>매일 한국 시간 12:17 집계. 새로고침은 저장된 집계를 읽으며 서버 집계를 다시 실행하지 않습니다.</p></div></div>');
}
export function revenueCard(docs, view) {
  const data = docs.summary.coverage?.ads; const available = data?.status === 'available' || data?.status === 'empty';
  const revenue = available ? sum(view.cur('adRevenue')) : null; const impressions = sum(view.cur('adImpressions'));
  const current = periodData(docs, view)?.current;
  return card('수익과 사용 가치', '실제 집계된 광고 수익만 사용 · 매출/원가의 전체 사업 손익과 다릅니다.', '<div class="stats"><div class="stat"><b>' + (revenue == null ? '—' : fmtMoney(revenue, docs.summary.currency ?? 'USD')) + '</b><span>기간 광고 수익</span></div><div class="stat"><b>' + (revenue == null || impressions <= 0 ? '—' : fmtMoney(revenue / impressions * 1000, docs.summary.currency ?? 'USD')) + '</b><span>광고 1,000회당 수익</span></div><div class="stat"><b>' + number(impressions) + '</b><span>광고 노출</span></div><div class="stat"><b>' + (current?.activeUsers > 0 ? fmtDur(current.engagementSec / current.activeUsers) : '—') + '</b><span>기간 활성 사용자당 참여시간</span></div></div><p class="sub">광고 수익 미연결은 수익 0원이 아닙니다. 광고 비용·서버비·결제 매출은 연결되지 않아 순이익이나 국가별 ROI를 계산하지 않습니다.</p>');
}
export function mountCountryChart(root, docs, view, ui) {
  const host = root.querySelector('#ch-country'); if (!host) return null;
  const trend = docs.operations?.countryTrend;
  const rows = [...(periodData(docs, view)?.countries ?? [])].sort((a, b) => ui.marketSort === 'newUsers' ? b.newUsers - a.newUsers : b.activeUsers - a.activeUsers);
  const name = ui.country ?? rows[0]?.name;
  const item = trend?.series?.[name];
  if (!item) { host.innerHTML = empty('선택 국가의 일별 추이가 아직 없습니다.'); return null; }
  const cutoff = view.dates[0]; const first = trend.dates.findIndex((d) => d >= cutoff); const start = first < 0 ? trend.dates.length : first;
  return lineChart(host, { dates: trend.dates.slice(start), title: name + ' 일간 활성 사용자', height: 210,
    series: [{ key: 'country', label: localizeName('country', name), color: COLORS.dau, values: item.dau.slice(start), area: true }], valueFmt: (v) => fmtInt(v) + '명' });
}
