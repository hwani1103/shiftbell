// admin_dashboard/public/assets/js/labels.js - 이벤트/분포 항목의 한국어 이름·아이콘·그룹.
// 사용자 정의 이벤트 이름은 앱의 lib/services/app_analytics.dart(AppAnalytics)와 반드시 같아야 한다.

/** group: 화면에서 묶어 보여 주는 분류. system=구글이 자동 수집하는 기본 이벤트 */
export const EVENT_META = {
  // ── 기본(자동 수집) ──
  first_open: { label: '앱 설치(첫 실행)', icon: '📲', group: 'system', desc: '앱을 처음 실행한 횟수. 설치 수로 봅니다(재설치 포함).' },
  app_remove: { label: '앱 삭제', icon: '🗑️', group: 'system', desc: '기기에서 앱이 삭제된 횟수. 구글 집계 특성상 실제보다 적을 수 있어요.' },
  session_start: { label: '세션 시작', icon: '▶️', group: 'system', desc: '앱을 켜서 사용을 시작한 횟수.' },
  screen_view: { label: '화면 조회', icon: '🖥️', group: 'system' },
  user_engagement: { label: '앱 사용(포그라운드)', icon: '⏳', group: 'system' },
  app_update: { label: '앱 업데이트', icon: '⬆️', group: 'system' },
  os_update: { label: 'OS 업데이트', icon: '🔄', group: 'system' },
  app_clear_data: { label: '앱 데이터 삭제', icon: '🧹', group: 'system' },
  app_exception: { label: '앱 오류(크래시)', icon: '⚠️', group: 'system' },
  ad_impression: { label: '광고 노출', icon: '📢', group: 'system' },
  ad_click: { label: '광고 클릭', icon: '👆', group: 'system' },
  notification_receive: { label: '알림 수신', icon: '🔔', group: 'system' },
  notification_open: { label: '알림 열기', icon: '📬', group: 'system' },
  // ── 사용자 행동(앱에 계측한 이벤트) ──
  onboarding_complete: { label: '온보딩 완료', icon: '🚀', group: '시작' },
  backup_restored: { label: '백업 복원', icon: '♻️', group: '백업' },
  backup_created: { label: '백업 생성(직접)', icon: '💾', group: '백업' },
  alarm_template_saved: { label: '고정 알람 저장', icon: '⏰', group: '알람' },
  alarm_dismissed: { label: '알람 끄기', icon: '🔕', group: '알람', desc: '울린 알람을 끈 횟수. 알람이 실제로 쓰이는 정도를 보여 줘요.' },
  alarm_snoozed: { label: '알람 5분 연장', icon: '😴', group: '알람' },
  alarm_no_response: { label: '알람 무응답 종료', icon: '⌛', group: '알람', desc: '끄지 않아 자동 종료된 알람 횟수. 많으면 알람이 잘 안 들리거나 헛울림이 잦다는 신호예요.' },
  shift_assigned: { label: '근무 지정·변경', icon: '📅', group: '달력' },
  calendar_theme_changed: { label: '달력 테마 변경', icon: '🎨', group: '달력' },
  memo_saved: { label: '메모 저장', icon: '📝', group: '달력' },
  ot_saved: { label: 'OT·특근 기록', icon: '⏱️', group: '달력' },
  schedule_created: { label: '일정 생성', icon: '🗓️', group: '일정' },
  sleep_record_saved: { label: '수면 기록 저장', icon: '🌙', group: '수면' },
  friend_share_started: { label: '친구 공유 시작', icon: '👥', group: '공유' },
  friend_added: { label: '친구 추가', icon: '🤝', group: '공유' },
  tab_selected: { label: '탭 이동', icon: '🧭', group: '사용' },
  help_opened: { label: '도움말 열람', icon: '❓', group: '사용' },
};

export function eventMeta(name) {
  return EVENT_META[name] ?? { label: name, icon: '•', group: name.startsWith('firebase_') ? 'system' : '기타' };
}
export const isSystemEvent = (name) => eventMeta(name).group === 'system';

export const BREAKDOWNS = [
  { key: 'appVersion', label: '앱 버전', unit: '명' },
  { key: 'os', label: 'Android', unit: '명' },
  { key: 'device', label: '기기', unit: '명' },
  { key: 'language', label: '언어', unit: '명' },
  { key: 'country', label: '국가', unit: '명' },
];

const NAMES = {
  language: { Korean: '한국어', English: '영어', Japanese: '일본어', Chinese: '중국어', Spanish: '스페인어', Vietnamese: '베트남어', Thai: '태국어', Indonesian: '인도네시아어', German: '독일어', French: '프랑스어' },
  country: { 'South Korea': '대한민국', 'United States': '미국', Japan: '일본', Canada: '캐나다', Australia: '호주', China: '중국', Vietnam: '베트남', Thailand: '태국', Philippines: '필리핀', Germany: '독일', 'United Kingdom': '영국', Taiwan: '대만' },
};
export function localizeName(dim, name) {
  return NAMES[dim]?.[name] ?? name;
}
export const osLabel = (v) => (/^\d/.test(v) ? `Android ${v}` : v);

/** 차트/카드에 쓰는 의미 색(라이트·다크 공통) */
export const COLORS = {
  dau: '#4662D6', wau: '#0BB5A4', mau: '#8B5CF6',
  install: '#10B981', uninstall: '#F97316', net: '#3B82F6',
  ads: '#F59E0B', click: '#EC4899', revenue: '#22C55E',
  palette: ['#4662D6', '#0BB5A4', '#8B5CF6', '#F59E0B', '#EC4899', '#0EA5E9', '#94A3B8'],
};
