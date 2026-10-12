"""Reproducible evidence for this review; does not declare device or human PASS."""
import csv
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path
from review_release_20261006 import ROOT, OUT, resources

load = lambda p: json.loads(p.read_text('utf-8-sig'))
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
baseline = load(OUT/'시작_자료.json')
history = {}
history_files = []
for folder in ['의미검토_1차_2026-10-05', '자연스러움검토_2차_2026-10-05',
               '독립최종검토_3차_2026-10-05', '후속재점검_2026-10-05']:
    path = ROOT/'docs/next_version'/folder/('후속_문구원장.csv' if folder.startswith('후속') else '문구_변경원장.csv')
    history_files.append(path)
    for row in csv.DictReader(path.open(encoding='utf-8-sig', newline='')):
        lang = row.get('언어', row.get('언어·지역', '')).split('-')[0]
        history.setdefault((lang, row['키']), []).append({'원장': folder, **row})

sources = {p.relative_to(ROOT).as_posix(): p.read_text('utf-8')
           for base in ['lib', 'android/app/src', 'web'] for p in (ROOT/base).rglob('*')
           if p.is_file() and p.suffix in {'.dart', '.kt', '.xml', '.html', '.js'}
           and 'generated' not in p.parts and p.name not in {'korean_only_copy.dart', 'locale_bootstrap.js'}}
index = {}
hardcodes = []
for path, source in sources.items():
    for line_num, line in enumerate(source.splitlines(), 1):
        if line.lstrip().startswith(('//', '*', '<!--')):
            continue
        for key in set(re.findall(r'(?:\.|@string/|@array/)\s*(\w+)', line)):
            index.setdefault(key, []).append(f'{path}:{line_num}')
        if re.search('[가-힣]', line) and re.search('[\x27\"]', line):
            hardcodes.append([path, line_num, line.strip(), '검색 후보; 언어혼입_도달검증.txt의 실제 기능별 조건과 대조. 로그/주석/데이터 포함'])

def write_csv(name, fields, rows):
    with (OUT/name).open('w', encoding='utf-8-sig', newline='') as handle:
        writer = csv.writer(handle)
        writer.writerow(fields)
        writer.writerows(rows)

candidate = {'permissionOpenFailed': 'U02', 'permissionNotApplicable': 'U07',
             'settingsPaydayBasisDesc': 'U08', 'workHoursLegacyClockTimeHint': 'U03',
             'helpBackupRestoreOldBackupFailTitle': 'U11', 'helpBackupRestoreOldBackupFailBody': 'U11',
             'restoreInterruptedCopyLost': 'U01', 'helpStartOnboardingBody': 'U04',
             'helpAlarmAlarmNotRingingBody': 'U05', 'helpTroubleshootAlarmIssueBody': 'U05',
             'publicWebShareBody': 'U06/U10', 'alarmSchedulePartialFailed': 'U13',
             'settingsScheduleChangeFailedWithError': 'U12'}
reasons = {'U02': '권한별 공통 설정 열기 실패가 특별 접근 권한까지 안내하도록 수정. 설정 검색+알림 수동 경로; 허용 판정 불변.',
           'U03': '첫 외국어 출시에는 구형 시간 저장 안내를 제공하지 않음. 한국어 원문/시간 데이터 보존, 공통 5언어에서 함께 제거.',
           'U07': 'PT 해당 없음에 별도 설정이라는 범위를 명시. 다른 언어는 이미 그 뜻이므로 유지.',
           'U08': 'EN/HI 시작일 한정 암시 제거. 실제 시작일·종료일 기준 모두 지원. PT/DE는 이미 중립적 기준일이므로 유지.',
           'U11': '아주 오래된 앱 버전 백업 항목은 한국어 전용으로 보존. 외국어의 일반 백업·재설치·복원 실패 안내는 유지.',
           'U12': '번역 자체 유지. 팀 저장/재생성 2곳의 raw error 인자만 현재 언어 오류로 대체; 한국어 상세와 진단 로그 보존.',
           'U13': '부분 실패의 실제 호출 조건상 total>=2. 3차 상세 사유와 현재 코드 일치. failed 단수/복수 유지.',
           'U01': '사본 소실은 safeEnd 성공 이후만 안내. 재예약 실패는 별도 미완료 예외/문구. 완료 의미가 실제 코드와 일치.',
           'U04': '문장 전체에 네 번째 권한과 앱 내 설정 경로 포함. 취향에 의한 재배열 불필요.',
           'U05': '최초 설정 중이라는 조건으로 Next 안내. 일반 설정 시트에 Next가 있다고 말하지 않음.',
           'U06/U10': 'HI 새/최신 차이는 문맥상 같은 공유 갱신 의미. 문구 유지; 웹 shell metadata에서 해당 현지화 문구 재사용.'}
rows = []
chains = []
for lang in ['pt', 'de', 'en', 'hi']:
    current = resources(lang)
    for item in baseline['resources'][lang]:
        key, res, before = item['key'], item['resource'], item['text']
        after = current.get((res, key), '')
        action = '삭제·한국어 분리' if (res, key) not in current else '수정' if before != after else '유지'
        cid = candidate.get(key, '')
        chain = history.get((lang, key), [])
        chains.append({'언어': lang, '리소스': res, '키': key, '이전_원문행': chain})
        details = '\n'.join(json.dumps(r, ensure_ascii=False) for r in chain)
        rows.append([lang, res, key, action, before, after, cid,
                     reasons.get(cid, '현재 외국어 제공 기능/공개 웹 또는 공통 native 알람·위젯 문구. 외국어 독해→한국어 의미·현재 호출 대조 후 유지.'),
                     '; '.join(index.get(key.split('[')[0], [])) or '정적 직접 호출 없음/배열·동적 리소스 식별자; 삭제 확정 근거로 삼지 않음',
                     details, '역번역_선기록.txt; 후보_판정.txt; 언어혼입_도달검증.txt',
                     '정적·호스트 검사 범위. 실기기/원어민 검수 NOT_RUN'])
write_csv('후속_문구원장.csv', ['언어','리소스','키','판정','변경 전','변경 후','후보','상세 사유','현재 참조','1·2·3차→후속 원문 연결','대조 근거','검증 한계'], rows)
(OUT/'이전판정_전체연결.json').write_text(json.dumps(chains, ensure_ascii=False, indent=2), 'utf-8')

old_ko = {(r['resource'], r['key']): r['text'] for r in baseline['resources']['ko']}
prior = list(csv.DictReader((ROOT/'docs/next_version/후속재점검_2026-10-05/한국어_분리보존원장.csv').open(encoding='utf-8-sig')))
prior_copy = {r['키']: r['보존 문구'] for r in prior}
scoped = load(ROOT/'lib/l10n/korean_only/messages_ko.json')
ko_rows = []
for key, value in scoped.items():
    if key.startswith('@'): continue
    original = prior_copy.get(key, old_ko.get(('arb', key)))
    assert original == value, key
    ko_rows.append([key, original, value, 'lib/l10n/korean_only/messages_ko.json', candidate.get(key, '기존 분리 유지'), '원문 동일'])
for node in ET.parse(ROOT/'android/app/src/main/res/values/korean_only.xml').getroot():
    key, value = node.attrib['name'], node.text
    assert prior_copy[key] == value
    ko_rows.append([key, prior_copy[key], value, 'android/app/src/main/res/values/korean_only.xml', '기존 분리 유지', '원문 동일'])
write_csv('한국어_분리보존원장.csv', ['키','변경 전','보존 문구','위치','후보','검사'], ko_rows)
write_csv('하드코딩_현재검색목록.csv', ['파일','행','검색 내용','판정 방법'], hardcodes)
write_csv('코드_변경원장.csv', ['후보','대상','변경','보존·검증'], [
    ['U03','lib/screens/work_hours_settings_screen.dart','구형 시간 안내를 koOnly로 읽고 한국어 조건 추가','임시 DB 480분 불변; ko→외국어→ko 문구 검사'],
    ['U11','lib/screens/help_screen.dart','구형 버전 백업 항목 koreanOnly 및 전용 Copy','한국어 검색/상세 유지, 외국어 검색/열린 상세 차단'],
    ['U09','lib/web_main.dart; lib/widgets/public_web_load_failure.dart','비동기 결과에 실패 enum 저장, build 시 번역','실패3종 및 완료 전후 언어 전환; 서버/공유 원문 불변'],
    ['U10','web/index.html; web/manifest.json; web/l10n/metadata_ko.json; generated web assets','초기 브랜드와 locale bootstrap/언어별 manifest','한국어 원문 보존; primary8종·언어 변경 Node 검사; 실제 설치 NOT_RUN'],
    ['U10','android/app/src/{dev,prod}/res/values-{pt,de,hi}/strings.xml','app_name 브랜드 6개 명시','기존 ko/en/default 보존; 구조 검사 및 native locale-list 호스트'],
    ['U12','lib/screens/all_teams_setup_screen.dart; lib/screens/team_schedule_edit_screen.dart','raw exception 변수→localizedErrorDetail; 원인 debug 로그','한국어 상세/저장 동작 불변; 언어별 오류 표시 검사'],
    ['U14','NotificationLocale.kt; NotificationHelper.kt; AlarmGuardReceiver.kt; RestoreGate.kt; ReleaseLocalePolicy.kt; MainActivity.kt','기존 알림 제작 문구/기존 채널 이름을 현재 locale로 갱신','새 알림/새 채널/차단해제 없음; PendingIntent/사용자 내용 보존, fullscreen 재실행 금지'],
    ['U14','InAppAlarmController.kt; AlarmOverlayService.kt; RingingAlarmTracker.kt; AppTextScale.kt','열린 제어 UI locale 갱신; 부모 locale 명시; 같은 live 회차 아래 알림 갱신','회차/원래 deadline/DB/예약 보존; G1/Cover 기능 회귀; 기기 미검증'],
    ['U15','android/app/src/main/res/layout/activity_alarm.xml; overlay_alarm.xml','snooze/dismiss Button에 기존 현지화 접근성 이름 연결','시각 배치/크기 불변; InApp 열린 창 locale 변경 기능 검사'],
    ['검사','tools/check_critical_release.ps1; tools/audit_l10n_resources.py; test/final_locale_tuning_test.dart; native tests','새 생성기·외국어 앱 이름·언어 전환 기능 검사 연결','레이아웃 테스트 추가/실행 없음'],
])
extra_resources = []
for flavor in ['dev', 'prod']:
    for lang in ['pt', 'de', 'hi']:
        path = f'android/app/src/{flavor}/res/values-{lang}/strings.xml'
        assert path not in baseline['sha256'], path
        value = ET.parse(ROOT/path).getroot().find("string[@name='app_name']").text
        extra_resources.append(['U10', lang, path, 'app_name', '지역 파일 없음; 기본 브랜드에 의존', value,
                                '동일 브랜드 명시; 한국어/기존 default/en 원문 불변'])
for lang in ['ko', 'pt', 'de', 'en', 'hi']:
    path = f'web/manifest_{lang}.json'
    manifest = load(ROOT/path)
    extra_resources.append(['U10', lang, path, 'name / short_name / description', '언어별 manifest 없음; 공통 한국어 manifest 사용',
                            json.dumps({k:manifest[k] for k in ['name','short_name','description']}, ensure_ascii=False),
                            '생성기 소유; 검토된 common 문구 재사용. 한국어 metadata 원문 별도 보존'])
write_csv('별도_리소스원장.csv', ['후보','언어','파일','키','변경 전 구조','변경 후','사유'], extra_resources)

preserved = {}
for name, before in baseline['sha256'].items():
    if any(folder in name for folder in ['의미검토_1차_', '자연스러움검토_2차_', '독립최종검토_3차_']) or name.endswith(('후속_문구원장.csv', '한국어_분리보존원장.csv')):
        assert (ROOT/name).exists() and digest(ROOT/name) == before, name
        preserved[name] = before

counts = Counter(row[3] for row in rows)
summary = {'review_order': ['pt-BR','de','en','hi'], 'baseline_foreign_entries': len(rows),
           'decisions': dict(counts), 'current_foreign_entries': sum(len(resources(lang)) for lang in ['pt','de','en','hi']),
           'common_arb_per_locale': len([k for k in scoped if not k.startswith('@')]),
           'korean_only_arb': len(ko_rows)-11, 'korean_only_native': 11,
           'korean_preserved': len(ko_rows), 'hardcoded_search_candidates': len(hardcodes),
           'historical_files_byte_identical': preserved,
           'device': 'NOT_RUN', 'native_speaker': 'NOT_RUN', 'layout': 'EXCLUDED_BY_USER'}
summary['common_arb_per_locale'] = len([r for r in resources('pt') if r[0]=='arb'])
current_ko = resources('ko')
ko_differences = []
for (res, key), value in old_ko.items():
    after = current_ko.get((res, key), scoped.get(key) if res == 'arb' else None)
    if after != value:
        ko_differences.append(key)
assert ko_differences == ['permissionOpenFailed'], ko_differences
summary['korean_common_intentional_change'] = ko_differences
summary['app_name_foreign_explicit_additions'] = 6
summary['changed_existing_files_since_start'] = [name for name, before in baseline['sha256'].items()
    if (ROOT/name).exists() and digest(ROOT/name) != before]
(OUT/'집계와_보존검사.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), 'utf-8')
print(json.dumps({k:v for k,v in summary.items() if k not in ['historical_files_byte_identical', 'changed_existing_files_since_start']}, ensure_ascii=False, indent=2))
