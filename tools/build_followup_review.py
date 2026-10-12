"""Record the follow-up decisions without modifying earlier ledgers."""
import csv,json,re,hashlib,xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/next_version/후속재점검_2026-10-05'
load=lambda p:json.loads(p.read_text('utf-8'))
baseline=load(OUT/'시작_자료.json')
native_before=load(ROOT/'docs/next_version/독립최종검토_3차_2026-10-05/시작_리소스.json')
scoped=load(ROOT/'lib/l10n/korean_only/messages_ko.json')
history={}
for directory in ['의미검토_1차_2026-10-05','자연스러움검토_2차_2026-10-05','독립최종검토_3차_2026-10-05']:
 for r in csv.DictReader((ROOT/'docs/next_version'/directory/'문구_변경원장.csv').open(encoding='utf-8-sig')):
  language=r['언어·지역'].split('-')[0]
  reason=r.get('뜻·결정 근거',r.get('뜻·채택 또는 유지 이유',r.get('채택 또는 유지 이유','')))
  history.setdefault((language,r['키']),[]).append(r['검토 ID']+' | '+reason)
sources={}
for directory,suffix in [('lib','*.dart'),('android/app/src/main','*.kt'),('android/app/src/main','*.xml'),('android/app/src/prod','*.xml'),('android/app/src/dev','*.xml')]:
 for p in (ROOT/directory).rglob(suffix):
  if 'generated' in p.parts or p.name=='korean_only_copy.dart':continue
  sources[p.relative_to(ROOT).as_posix()]=p.read_text('utf-8')
indices={False:{},True:{}}
for file,code in sources.items():
 for i,line in enumerate(code.splitlines(),1):
  if line.lstrip().startswith(('//','*')):continue
  for native,pattern in [(False,r'\.\s*(\w+)'),(True,r'(?:R\.(?:string|array)\.|@(?:string|array)/)(\w+)')]:
   for key in set(re.findall(pattern,line)):
    indices[native].setdefault(key,[]).append(f'{file}:{i} | {line.strip()}')
def refs(key,native=False):return '\n'.join(indices[native].get(key.split('[')[0],[]))
def scope(key):
 if 'OneTap' in key or key.startswith(('oneTap','customAlarm','helpOneTap')):return 'F04 원터치: custom/preset 생성은 한국어 UI; 외국어 신규 설치에는 충돌 조건 없음; 추가 언어 가드'
 if key.startswith(('friend','helpFriend','calendarFriend','commonShare','commonCopy')):return 'F03 앱 친구 공유: 한국어 진입 전 래퍼 및 비동기 검사. 공개 웹 13키는 공통에 별도로 유지'
 if key.startswith(('theme','helpCalendarThemes')):return 'F06 한국어 전용 4종/외국어 6종; 선택·직접 미리보기·언어 변경 제한'
 if key.startswith(('helpCondition','helpSleep','onboardingCondition')):return 'F02 수면·회복: 한국어 탭·전체보기·입력; 네이티브 위젯/수신기/자동감지 조건'
 if 'ScheduleTab' in key or key.startswith(('navScheduleManagement','schedule','disableTab')):return 'F01 개인 일정: 한국어 진입 전 래퍼·도움말·알림·지연 팝업 조건'
 return 'F00 현재 사용처 제거/미사용: 현재 Flutter 소스에 공통 생성 API/동적 ARB 접근 없음; 한국어 원본만 보존'
def flatten(tree):
 result={}
 for n in tree:
  if n.tag=='string-array':
   for i,x in enumerate(n):result[f'{n.attrib["name"]}[{i}]']=x.text or ''
  else:result[n.attrib['name']]=n.text or ''
 return result
rows=[]
for lang in ['pt','de','en','hi']:
 old=baseline['arbs'][lang];current=load(ROOT/f'lib/l10n/app_{lang}.arb')
 for key in [k for k in old if not k.startswith('@')]+[k for k in current if not k.startswith('@') and k not in old]:
  before=old.get(key,'');after=current.get(key,'')
  action='삭제' if key not in current else '신규' if key not in old else '수정' if before!=after else '유지'
  reason=scope(key) if action=='삭제' else 'AK 네 번째 권한/개별 설정 흐름·상태 확인 실패를 거절로 단정하지 않음' if key.startswith('permission') or key=='privacyPermissionsBody' or (before!=after and key.startswith(('helpStart','helpAlarm','helpTroubleshoot'))) else '공개 웹 루트의 한국어 하드코딩을 언어별 공개 소개로 분리' if key.startswith('publicWeb') else '공휴일 기능 미제공이므로 관련 제목·설명 제거; 주 시작일·주말·근무시간 집계 보존' if before!=after else '실제 제공 기능/공개 웹 의존성이 있어 유지; 취향만으로 바꾸지 않음'
  if action=='삭제' and key=='fixedAlarmSkippedByOneTap':reason+='; 3차 일반화 4건 철회. 기존 표시 코드는 언어 직접 차단이 아니라 custom 충돌 조건이었다.'
  position=refs(key)
  rows.append([lang,'Flutter ARB',key,action,before,after,f'lib/l10n/app_{lang}.arb',position or '(현재 정적 멤버 호출 없음; F00/분리 후보와 소스 전수 대조)',reason,'\n'.join(history.get((lang,key),[])), '기존 채택을 삭제/후속 분기로 대체' if action in ['삭제','수정'] and history.get((lang,key)) else '이전 사유를 보존; 후속 기능 범위로 재확인', '한국어 의미·현재 소스·AK/AJ; 기능_도달경로.txt; 리소스_자동검사.json','정적 추적/자동 검사; 실기기 미수행'])
 folder='values' if lang=='en' else 'values-'+lang
 path=f'android/app/src/main/res/{folder}/strings.xml'
 old=flatten(ET.fromstring(native_before[path.replace('/','\\')]['text']))
 current=flatten(ET.parse(ROOT/path).getroot())
 for key,before in old.items():
  action='유지' if key in current else '삭제'
  reason='알람 화면·제어·상태/실패 알림·달력 위젯/미리보기에서 외국어 신규 사용자에게 필요' if action=='유지' else 'F02/F01 한국어 전용 위젯·개인 일정 알림 또는 F04 원터치 라벨. dedicated korean_only.xml 보존; 모든 사용 조건은 기능_도달경로.txt 참조'
  rows.append([lang,'Android XML',key,action,before,current.get(key,''),path,refs(key,True) or '(배열/메타데이터 참조)',reason,'\n'.join(history.get((lang,key),[])),'기존 번역 채택보다 기능별 실제 도달 범위를 우선' if action=='삭제' else '기존 결정 유지','현재 네이티브 코드·Manifest·XML·ReleaseLanguagesTest','정적 추적/Robolectric; 실제 런처/잠금 기기 미확인'])
headers=['언어','리소스','키','판정','변경 전','변경 후','리소스 위치','현재 호출 위치·조건','삭제·분기·유지 이유','1·2·3차 연결 ID·상세 사유','기존 결정과 차이','출처·근거','검증 수준']
with (OUT/'후속_문구원장.csv').open('w',encoding='utf-8-sig',newline='') as f:
 w=csv.writer(f);w.writerow(headers);w.writerows(rows)
with (OUT/'한국어_분리보존원장.csv').open('w',encoding='utf-8-sig',newline='') as f:
 w=csv.writer(f);w.writerow(['키','변경 전','보존 문구','새 위치','호출 위치','보존 근거'])
 for k,v in scoped.items():
  if not k.startswith('@'):w.writerow([k,baseline['arbs']['ko'][k],v,'lib/l10n/korean_only/messages_ko.json',refs(k),scope(k)])
 for n in ET.parse(ROOT/'android/app/src/main/res/values/korean_only.xml').getroot():w.writerow([n.attrib['name'],n.text,n.text,'android/app/src/main/res/values/korean_only.xml',refs(n.attrib['name'],True),'한국어 기능 전용; 공유 native 화면은 KoreanFeatureStrings로 외국어 기본 라벨 사용'])
counts=Counter(r[3] for r in rows)
summary={'foreign_original_entries':2944,'decisions':dict(counts),'foreign_current_common_entries':4*(507+44),'korean_arb_moved_unchanged':199,'korean_native_moved':11,'foreign_hardcoded_one_tap_removed':25,'foreign_hardcoded_personal_schedule_removed':5,'new_common_per_language':25,'new_permission_keys_per_language':19,'new_public_web_keys_per_language':6,'scope':'Counts are resource entries per language, not file counts; hardcoded removals are separate.'}
(OUT/'집계.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),'utf-8')
hashes={file:hashlib.sha256((ROOT/file).read_bytes()).hexdigest() for file in sources}
for p in (ROOT/'lib/l10n').rglob('*.arb'):hashes[p.relative_to(ROOT).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
for p in [*(ROOT/'test').rglob('*.dart'),*(ROOT/'lib/l10n/generated').glob('*.dart'),ROOT/'lib/l10n/korean_only/messages_ko.json',ROOT/'lib/l10n/korean_only_copy.dart',ROOT/'l10n.yaml',ROOT/'tools/check_critical_release.ps1',ROOT/'tools/audit_l10n_resources.py',ROOT/'tools/generate_korean_only_copy.py']:
 hashes[p.relative_to(ROOT).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
(OUT/'최종_소스리소스_해시.json').write_text(json.dumps(hashes,ensure_ascii=False,indent=2),'utf-8')
hardcodes=[]
for file,code in sources.items():
 for i,line in enumerate(code.splitlines(),1):
  if line.lstrip().startswith(('//','*','<!--')):continue
  if not re.search('[가-힣]',line) or not re.search('[\x27\"]',line):continue
  if any(token in line for token in ['print(','debugPrint(','Log.','throw ','Exception(']):decision='개발 로그/내부 예외. 사용자 노출 실패 설명은 localizedErrorDetail로 분리'
  elif any(token in file for token in ['condition','sleep','Sleep','evidence','schedule_management','custom_alarm','CustomAlarm']):decision='한국어 전용 기능 또는 그 데이터/진단. F01/F02/F04 진입·수신 조건 추적; 한국어/사용자 데이터 보존'
  elif file=='lib/main.dart':decision='한국어 전용 디버그 화면/비노출 데이터·설정 문자열. 공개 라우트 없음; 직접 build 언어 차단'
  elif file=='lib/screens/settings_tab.dart':decision='한국어 기능 재활성화 항목의 ko 조건 또는 로그/데이터. 메뉴·콜백 조건 별도 확인'
  elif file.endswith('.xml'):decision='한국어 전용 리소스/한국어 런처 이름 또는 XML 주석. 기본 알람 레이아웃의 주간 하드코딩은 공통 alarm_default_label로 교체'
  else:decision='내부 식별자/한글 원본·사용자 데이터 또는 설명 주석 후보; 이 행 자체는 노출/삭제 확정 근거가 아님'
  hardcodes.append([file,i,line.strip(),decision])
with (OUT/'하드코딩_전수검색목록.csv').open('w',encoding='utf-8-sig',newline='') as f:
 w=csv.writer(f);w.writerow(['파일','행','코드','분류·한계']);w.writerows(hardcodes)
print(json.dumps(summary,ensure_ascii=False));print('Hardcoded candidates',len(hardcodes))
