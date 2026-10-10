import { lineChart, sparkline } from './charts.js';
import { fmtInt, fmtPct, fmtMoney, fmtDur, fmtMD, esc, sum, avg, deltaInfo } from './format.js';
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
export function operatingBrief(docs, view) {
  const period = periodData(docs, view); const notes = [];
  const current = period?.current?.activeUsers; const previous = period?.previous?.activeUsers;
  if (current != null && previous > 0) {
    const ratio = (current - previous) / previous;
    notes.push({ tone: ratio < -.2 && previous >= 30 ? 'warning' : '', title: '사용자 기반', body: '동일 기간 활성 사용자 ' + fmtInt(current) + '명, 직전 ' + fmtInt(previous) + '명 (' + (ratio >= 0 ? '+' : '') + (ratio * 100).toFixed(1) + '%).' });
  } else notes.push({ title: '비교 기준 확보', body: '기간별 중복 제거 이용자 집계가 연결되면 성장과 감소를 비교할 수 있습니다.' });
  const failures = eventData(docs, view, 'alarm_schedule_failed');
  if (failures.count > 0) notes.push({ tone: 'warning', title: '예약 실패 관측', body: fmtInt(failures.count) + '회의 예약 API 실패가 보고되었습니다. 알람·기기에서 제조사별 관측을 확인하세요. 실제 미울림 횟수와 같지 않습니다.' });
  const teams = eventData(docs, view, 'team_roster_created');
  if (!teams.observed) notes.push({ title: '전체교대조 계측', body: '생성·수정·삭제 이벤트를 연결했습니다. 새 계측 앱이 출시되고 사용된 이후부터 데이터가 들어옵니다.' });
  const age = Date.now() - Date.parse(docs.summary.updatedAt);
  if (age > 36 * 3600000) notes.unshift({ tone: 'warning', title: '집계 지연', body: '마지막 성공 집계가 36시간 이상 지났습니다. 데이터 수집 상태에서 확인하세요.' });
  return '<section class="ops-brief span-12"><div class="eyebrow">SERVICE OPERATIONS</div><h1>서비스가 성장하고, 제대로 쓰이고 있는가</h1><p class="brief-sub">' + esc(view.dates[0]) + ' — ' + esc(view.dates.at(-1)) + ' · 완료된 날짜 기준 · 출시 앱</p><div class="brief-grid">' + notes.slice(0, 3).map((n) => '<article class="brief-item ' + (n.tone ?? '') + '"><b>' + n.title + '</b><p>' + esc(n.body) + '</p></article>').join('') + '</div></section>';
}
const FEATURES = [
  ['onboarding_complete', '시작 완료'], ['team_roster_created', '전체교대조 생성'], ['all_shifts_opened', '전체근무표 열람'],
  ['shift_assigned', '근무 변경'], ['alarm_template_saved', '알람 설정'], ['alarm_dismissed', '알람 끄기'],
  ['memo_saved', '메모'], ['ot_saved', 'OT·특근'], ['sleep_record_saved', '수면 기록'], ['friend_share_started', '친구 공유 시작'],
  ['backup_created', '직접 백업'], ['help_opened', '도움말'],
];
export function adoptionCard(docs, view) {
  const totalUsers = periodData(docs, view)?.current?.totalUsers;
  const rows = FEATURES.map(([name, label]) => {
    const data = eventData(docs, view, name);
    const share = data.users != null && totalUsers > 0 && data.users <= totalUsers ? data.users / totalUsers : null;
    return '<tr data-action="event" data-event="' + name + '" tabindex="0" role="button" aria-label="' + label + ' 상세"><th>' + label + '</th><td>' + (data.observed ? number(data.users, '명') : tag('미관측')) + '</td><td>' + (share == null ? '—' : '<div class="adoption"><i style="width:' + (share * 100) + '%"></i><span>' + fmtPct(share, 1) + '</span></div>') + '</td><td>' + (data.observed ? number(data.count, '회') : '—') + '</td></tr>';
  }).join('');
  return card('핵심 기능의 도달과 활용', '선택 기간 내 기능별 사용자 수와 이용 횟수. 기능 간 사용자는 중복되며 전환 퍼널이 아닙니다.', '<div class="table-scroll"><table class="ops-table"><thead><tr><th>기능</th><th>사용자</th><th>기간 이용자 대비</th><th>이용 횟수</th></tr></thead><tbody>' + rows + '</tbody></table></div><p class="sub">기능 사용률의 분모는 같은 기간의 전체 이용자(totalUsers)입니다. 미관측은 미사용·구버전·수집 누락을 구분할 자료가 아직 없다는 뜻입니다.</p>');
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
