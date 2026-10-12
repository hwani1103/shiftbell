"""Create candidates BEFORE reading prior detailed reasons; do not edit resources."""
import json, re, csv
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'docs/next_version/후속재점검_2026-10-05'
start=json.loads((OUT/'시작_자료.json').read_text('utf-8'))
keys=[k for k in start['arbs']['ko'] if not k.startswith('@')]
web=(ROOT/'lib/web_main.dart').read_text('utf-8')+(ROOT/'lib/widgets/friend_web_calendar.dart').read_text('utf-8')
web_keys={k for k in keys if re.search(r'\.'+re.escape(k)+r'\b',web)}
unused=list(csv.DictReader((ROOT/'docs/next_version/독립최종검토_3차_2026-10-05/직접호출_미발견.csv').open(encoding='utf-8-sig')))
unreferenced={r['키'] for r in unused}
explicit={'fixedAlarmSkippedByOneTap','navScheduleManagement','scheduleTabDisableExtraNotice',
 'settingsScheduleTabReenableTitle','settingsScheduleTabReenableSubtitle','onboardingScheduleTabPopupTitle',
 'onboardingScheduleTabPopupBody','settingsResetScheduleSharingFailed','scheduleTabSyncFailed',
 'disableTabButtonLabel','disableTabDialogBody','commonShare','commonCopy'}
selected={k for k in keys if (k in explicit or k in unreferenced or
 re.match(r'customAlarm|oneTap|help(Sleep|Condition|Friend|ScheduleTab|OneTap)|helpTroubleshootFriend|theme(InitialBadge|Underline|EventChip|Editorial)',k) or
 k.startswith('friend') and k not in web_keys)}
selected-=web_keys
rows=[]
for k in keys:
 if k not in selected: continue
 scope='현재 제품 진입 없음' if k in unreferenced else (
  '원터치: 생성 UI 없음; 충돌 조건 자체는 언어 차단 아님' if k=='fixedAlarmSkippedByOneTap' else
  '한국어 전용 기능 진입/도움말/테마 범위')
 rows.append({'키':k,'후보':'한국어 전용 리소스 분리; 네 번역 삭제', '첫판단근거':scope,
  '호출위치':'; '.join(start['references'][k]),'웹뷰어':'공유 웹 직접/공통 컴포넌트 의존 없음',
  '필요조치':'외국어 신규 경로 비도달; 직접/열린/지연 경로 추가 차단 후 이동',
  '기존사유대조':'이 파일 작성 뒤 1·2·3차 상세 변경원장 대조'})
with (OUT/'수정후보_첫판단.csv').open('w',encoding='utf-8-sig',newline='') as f:
 writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
(OUT/'분리_후보.json').write_text(json.dumps(sorted(selected),ensure_ascii=False,indent=2),'utf-8')
print(len(selected),'Korean-only candidates; web dependencies retained:',sorted(web_keys & {k for k in keys if k.startswith('friend')}))
print('Selected:', ', '.join(sorted(selected)))
