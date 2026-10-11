// admin_dashboard/public/assets/js/labels.js - 이벤트/분포 항목의 한국어 이름·아이콘·그룹.
// 현재 이벤트는 앱의 AnalyticsEvent.all과 일치한다. retired:true는 과거 데이터 표시용이다.

/** group: 화면에서 묶어 보여 주는 분류. system=구글이 자동 수집하는 기본 이벤트 */
export const EVENT_META = {
  team_roster_created: { label: '전체교대조 생성', icon: '•', group: '달력', desc: '전체교대조 근무표 저장 완료. 근무명·조 이름·패턴 내용은 전송하지 않습니다.' },
  team_roster_changed: { label: '전체교대조 변경', icon: '•', group: '달력', desc: '저장 완료된 조 변경. 근무표 내용은 전송하지 않습니다.' },
  team_roster_deleted: { label: '전체교대조 삭제', icon: '•', group: '달력', desc: '전체교대조 설정 삭제 완료.' },
  alarm_schedule_ok: { label: '예약 API 완료', icon: '•', group: '알람', desc: '로컬 진단에서 관측된 예약 API 완료. 반복 예약/재시도 포함, 실제 울림 성공과 다릅니다.' },
  alarm_schedule_failed: { label: '예약 API 실패', icon: '•', group: '알람', desc: '예약 API 실패 관측. 이후 재시도 성공 여부와 실제 미울림을 뜻하지 않습니다.' },
  alarm_fired: { label: '알람 울림 진입', icon: '•', group: '알람', desc: '현재 회차 수신이 확인되어 울림 경로에 진입한 관측. 청취 성공을 뜻하지 않습니다.' },
  alarm_refresh_completed: { label: '알람 갱신 완료', icon: '•', group: '알람', desc: '네이티브 재예약 갱신 완료 관측. 부팅 이후만을 뜻하지 않습니다.' },
  alarm_refresh_failed: { label: '알람 갱신 실패', icon: '•', group: '알람', desc: '네이티브 갱신 실패 관측.' },
  device_boot_seen: { label: '부팅 신호 관측', icon: '•', group: '알람', desc: 'BOOT/LOCKED_BOOT 신호 관측. 동일 부팅에서 여러 신호가 올 수 있습니다.' },
  ops_daily_ready: { label: '권한 상태 정상 관측', icon: '•', group: '알람', desc: '하루 1회 관측한 필수 권한 상태. 실제 울림 성공을 보장하지 않습니다.' },
  ops_daily_restricted: { label: '권한 제한 관측', icon: '•', group: '알람', desc: '하루 1회 필수 권한 미허용 관측.' },
  ops_daily_unknown: { label: '권한 상태 확인 불가', icon: '•', group: '알람', desc: '하루 1회 권한 상태 확인 불가 관측.' },
  ops_battery_restricted: { label: '배터리 최적화 적용 관측', icon: '•', group: '알람', desc: '하루 1회 OS 최적화 적용 상태. 제조사 제한이나 실패 원인으로 확정하지 않습니다.' },
  ops_exact_denied: { label: '정확 알람 미허용 관측', icon: '•', group: '알람', desc: '하루 1회 정확 알람 미허용 관측.' },
  ops_notification_blocked: { label: '앱 알림 차단 관측', icon: '•', group: '알람', desc: '하루 1회 앱 알림 차단 관측.' },
  ops_channel_blocked: { label: '알람 채널 차단 관측', icon: '•', group: '알람', desc: '하루 1회 알람 채널 차단 관측.' },
  ops_fullscreen_denied: { label: '전체화면 미허용 관측', icon: '•', group: '알람', desc: '하루 1회 전체화면 알림 미허용 관측.' },

  one_tap_opened: { retired: true, label: '원터치 패널 열기', icon: '•', group: '알람', desc: '원터치 알람 버튼으로 패널을 연 횟수.' },
  one_tap_closed: { retired: true, label: '원터치 패널 닫기', icon: '•', group: '알람', desc: '뒤로가기·달력 탭·할당 완료로 패널을 닫은 횟수.' },
  one_tap_preset_editor_opened: { retired: true, label: '원터치 설정창 열기', icon: '•', group: '알람', desc: '추가 또는 수정 설정창을 연 횟수.' },
  one_tap_preset_saved: { retired: true, label: '원터치 설정 추가', icon: '•', group: '알람', desc: '새 원터치 시각·울림 설정 저장 완료 횟수. 실제 시각은 수집하지 않습니다.' },
  one_tap_preset_updated: { retired: true, label: '원터치 설정 수정', icon: '•', group: '알람', desc: '기존 원터치 설정 변경 저장 완료 횟수.' },
  one_tap_preset_deleted: { retired: true, label: '원터치 설정 삭제', icon: '•', group: '알람', desc: '원터치 설정 삭제 완료 횟수.' },
  one_tap_preset_cancelled: { retired: true, label: '원터치 설정 취소', icon: '•', group: '알람', desc: '설정창에서 저장 없이 나간 횟수.' },
  one_tap_preset_blocked: { retired: true, label: '원터치 수정 제한', icon: '•', group: '알람', desc: '미래 날짜에 이미 추가한 설정의 수정을 차단한 횟수.' },
  one_tap_preset_selected: { retired: true, label: '원터치 시각 선택', icon: '•', group: '알람', desc: '저장된 시각을 골라 날짜 선택으로 넘어간 횟수.' },
  one_tap_assigned: { retired: true, label: '원터치 예약 완료', icon: '•', group: '알람', desc: '실제 날짜에 예약 성공한 횟수. 예약 시도 전체와 구분됩니다.' },
  one_tap_assign_rejected: { retired: true, label: '원터치 예약 거부·실패', icon: '•', group: '알람', desc: '중복·지난 시각·예약 실패 등으로 추가하지 못한 횟수.' },
  one_tap_alarm_deleted: { retired: true, label: '원터치 날짜 알람 삭제', icon: '•', group: '알람', desc: '날짜에 추가된 원터치 알람의 삭제 완료 횟수.' },

  // ── 기본(자동 수집) ──
  first_open: { label: '첫 실행(first_open)', icon: '📲', group: 'system', desc: 'GA4 첫 실행 이벤트. 재설치와 Analytics 도입 버전으로 업데이트한 기존 사용자도 포함될 수 있어 순수 신규 설치 수와 다릅니다.' },
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
  custom_alarm_assigned: { retired: true, label: '원터치 예약 시도 전체', icon: '🗓️', group: '알람', desc: '원터치 예약 시도 횟수(성공·거부 포함). 예약 완료와 거부 항목에서 결과를 따로 볼 수 있어요.' },
  alarm_dismissed: { label: '알람 끄기', icon: '🔕', group: '알람', desc: '울린 알람을 끈 횟수. 알람이 실제로 쓰이는 정도를 보여 줘요.' },
  alarm_snoozed: { label: '알람 연장', icon: '😴', group: '알람' },
  alarm_no_response: { label: '알람 무응답 종료', icon: '⌛', group: '알람', desc: '끄지 않아 자동 종료된 알람 횟수. 많으면 알람이 잘 안 들리거나 헛울림이 잦다는 신호예요.' },
  shift_assigned: { label: '근무 지정·변경', icon: '📅', group: '달력' },
  calendar_theme_changed: { label: '달력 테마 변경', icon: '🎨', group: '달력' },
  memo_saved: { label: '메모 저장', icon: '📝', group: '달력' },
  ot_saved: { label: 'OT·특근 기록', icon: '⏱️', group: '달력' },
  schedule_created: { label: '일정 생성', icon: '🗓️', group: '일정' },
  sleep_record_saved: { label: '수면 기록 저장', icon: '🌙', group: '수면' },
  friend_share_started: { label: '친구 공유 시작', icon: '👥', group: '공유' },
  friend_added: { label: '친구 추가', icon: '🤝', group: '공유' },
  help_opened: { label: '도움말 열람', icon: '❓', group: '사용' },
  memo_edited: { label: '메모 수정', icon: '✏️', group: '달력' },
  memo_deleted: { label: '메모 삭제', icon: '🗑️', group: '달력' },
  schedule_edited: { label: '일정 수정', icon: '✏️', group: '일정' },
  schedule_deleted: { label: '일정 삭제', icon: '🗑️', group: '일정' },
  schedule_notification_changed: { label: '일정 알림 변경', icon: '🔔', group: '일정' },
  auto_backup_created: { label: '백업 생성(자동)', icon: '💾', group: '백업' },
  alarm_history_cleared: { label: '알람 이력 전체 삭제', icon: '🗑️', group: '알람' },
  all_shifts_opened: { label: '전체 근무표 열기', icon: '📋', group: '달력' },
  shift_name_changed: { label: '근무명 변경', icon: '🏷️', group: '달력' },
  shift_color_changed: { label: '근무 색상 변경', icon: '🎨', group: '달력' },
  alarm_sound_changed: { label: '알람음 변경', icon: '🎵', group: '알람' },
  friend_calendar_opened: { label: '친구 근무표 열기(앱)', icon: '👥', group: '공유' },
  sleep_record_edited: { label: '수면 기록 수정', icon: '✏️', group: '수면' },
  sleep_record_deleted: { label: '수면 기록 삭제', icon: '🗑️', group: '수면' },
  sleep_estimate_rejected: { label: '자동 수면 추정 거부', icon: '🚫', group: '수면' },
};

export function eventMeta(name) {
  return EVENT_META[name] ?? { label: name, icon: '•', group: name.startsWith('firebase_') ? 'system' : '기타' };
}
export const isSystemEvent = (name) => eventMeta(name).group === 'system';

export const BREAKDOWNS = [
  { key: 'appVersion', label: '앱 버전', unit: '명' },
  { key: 'os', label: 'Android', unit: '명' },
  { key: 'device', label: '기기', unit: '명' },
  { key: 'manufacturer', label: '제조사', unit: '명' },
  { key: 'language', label: '언어', unit: '명' },
  { key: 'country', label: '국가', unit: '명' },
];

const NAMES = {
  language: { Korean: '한국어', English: '영어', Japanese: '일본어', Chinese: '중국어', Spanish: '스페인어', Vietnamese: '베트남어', Thai: '태국어', Indonesian: '인도네시아어', German: '독일어', French: '프랑스어' },
  country: { India: '인도', Brazil: '브라질', 'United Arab Emirates': '아랍에미리트', 'South Africa': '남아프리카공화국', 'South Korea': '대한민국', 'United States': '미국', Japan: '일본', Canada: '캐나다', Australia: '호주', China: '중국', Vietnam: '베트남', Thailand: '태국', Philippines: '필리핀', Germany: '독일', 'United Kingdom': '영국', Taiwan: '대만' },
};
export function localizeName(dim, name) {
  return name === '(not set)' ? '확인 불가' : NAMES[dim]?.[name] ?? name;
}
export const osLabel = (v) => (/^\d/.test(v) ? `Android ${v}` : v);

/** 차트/카드에 쓰는 의미 색(라이트·다크 공통) */
export const COLORS = {
  dau: '#4662D6', wau: '#0BB5A4', mau: '#8B5CF6',
  install: '#10B981', uninstall: '#F97316', net: '#3B82F6',
  ads: '#F59E0B', click: '#EC4899', revenue: '#22C55E',
  palette: ['#4662D6', '#0BB5A4', '#8B5CF6', '#F59E0B', '#EC4899', '#0EA5E9', '#94A3B8'],
};
