"""Serialize completed manual review decisions; this is not a language reviewer."""
import csv
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/next_version/독립최종검토_3차_2026-10-05'
PRIOR = ROOT / 'docs/next_version/자연스러움검토_2차_2026-10-05'
LANGS = {'pt-BR': 'pt', 'de-DE': 'de', 'en-US/en-GB': 'en', 'hi-IN': 'hi'}
KEEP = {
    'C01': '저장·삭제·닫기·알람 종료의 결과를 구별한다. 기본 근무명은 법정 휴가나 업종별 제도를 약속하지 않는다. 취향에 따른 동의어 교체 근거 없음.',
    'C02': '근무명과 반복 순서의 위치를 구별하고 반복/불규칙 배정의 조작 순서를 보존한다. 실제 복원 진입 제목과 연결되므로 짧은 버튼과 모든 도움말의 어형을 억지로 통일하지 않는다(T03).',
    'C03': '알람 예약·현재 울림 종료·스누즈·이력 삭제를 구별한다. 이력 삭제가 예약 취소라는 약속을 만들지 않는다. 5분과 예약 기간 한정 유지(T05).',
    'C04': '한국어 전용 원터치 기능 리소스의 예약/프리셋/삭제 결과 의미는 보존하되 외국어판 진입과 도움말은 차단한다. 문구 존재를 제공 기능으로 판단하지 않는다.',
    'C05': '근무·메모·개인 일정의 의미를 구별한다. 메모 상한 변수는 호출부에서 3이므로 단수 분기 불필요(T02). 실제 날짜·시간 인자 보존.',
    'C06': '예정 근무시간·추가 근무시간을 구별하며 변경으로 늘어난 시간만 OT 요약에 더한다. 급여 계산이나 실제 출퇴근 기록 기능을 새로 약속하지 않는다.',
    'C07': '팀 이름/내 팀 선택/전체 팀표 재생성을 구별하고 내 근무·알람 유지와 재생성 대상의 경고 의미를 보존한다.',
    'C08': '복원은 저장 데이터 교체와 이력 병합을 구별하고 울림/스누즈 유지·중단 후 예약 불확실성을 보존한다. Restore 계열은 실제 진입 제목으로 찾을 수 있어 어형 통일 불필요(T03).',
    'C09': '한국어 전용 공유 리소스는 코드/링크·중지·서버 확인 대기를 구별한 기존 문장을 보존한다. 외국어 앱 사용자에게 공유 안내를 보여주는 예외는 추가하지 않는다.',
    'C10': '권한 거부·미확인·예약 실패를 성공으로 바꾸지 않는다. 영어 일부 실패는 failed < total 호출 조건상 total >= 2이므로 alarms 유지(T02).',
    'C11': '제공 기능의 로컬 저장·분석·광고·권한·파일 보관 설명을 대조한다. 실제 전송 여부나 법적 적합성의 신규 실증으로 계산하지 않는다.',
    'C12': '개인 일정은 네 언어 미제공. 저장된 번역의 시간/기간/알림 실패 의미는 유지하되 탭·튜토리얼·도움말·알림 생성 경로를 차단한다. 일정 상한은 3으로 단수 불필요(T02).',
    'C13': '수면·회복은 네 언어 미제공. 숨김 리소스 번역의 야간 수면 문단 누락(T01)은 현재 노출 문구에 추가하지 않는다. 향후 기능 제공 전 별도 재검토. 의료·법적 원문 감수 완료로 표시하지 않는다.',
    'C14': '외국어용 6개 테마명과 도움말·위젯 요일을 대조한다. 배열 저장 순서와 실제 지역별 표시 순서는 구별한다. 숨김 테마의 리소스를 임의 삭제하지 않는다.',
    'C15': '시작·업데이트·준비 중·실패를 구별하고 재시도를 성공으로 약속하지 않는다. 원시 error 인자까지 모두 번역되었다고 판단하지 않는다.',
    'C16': 'Android 종료·5분 연장·재울림 시각을 Flutter의 해당 동작과 대조한다. 힌디어 실제 버튼 5 मिनट बाद 연결과 독일어/포르투갈어 종료 동사 문맥 차이를 유지(T05).',
}

DECISIONS = {
    'statusPatternDayCycle': ('T02', '반복 순서에 근무 1개도 허용된다. pt의 1 dias와 de의 1-Tage를 ICU 단수로 수정한다. days 인자 및 복수 결과는 보존.', 'lib/screens/onboarding_screen.dart; lib/screens/settings_tab.dart'),
    'alarmSchedulePartialFailed': ('T02', 'partiallyFailed 조건은 0 < failed < attempted다. 실패 1개는 가능하므로 pt/de/hi 술어를 단수로 분기한다. total=1은 도달하지 않아 영어는 유지. 실패/전체 인자 순서와 재시도 지시 보존.', 'lib/services/alarm_service.dart; lib/screens/calendar_tab.dart'),
    'teamEditPositionsOn': ('T04', '이 화면은 패턴 위치만이 아니라 요일별 규칙 모드의 실제 근무도 표시한다. 네 언어 제목을 해당 날짜의 팀 근무로 넓힌다. date 인자는 보존.', 'lib/screens/team_schedule_edit_screen.dart'),
    'helpAlarmAlarmHistoryBody': ('T06', '네이티브 스누즈의 5분 뒤 시각에 다른 알람이 이미 있으면 현재 알람은 종료되고 다른 알람은 유지된다. 무조건 재예약되는 것으로 읽히던 도움말에 이 결과를 추가한다. 힌디어 실제 버튼 표현 유지.', 'android/app/src/main/kotlin/com/hwani1103/shiftbell/AlarmActionHelper.kt; lib/screens/help_screen.dart'),
}
SCOPE_KEYS = {
    'fixedAlarmSkippedByOneTap': '충돌한 알람의 미제공 생성 기능을 광고하지 않고 기존 알람과 같은 시각이라 근무 알람을 건너뛰었다는 결과만 설명.',
    'settingsAllAlarmsWillBeDeleted': '미제공 원터치 프리셋 설명 제거. 모든 알람/근무별 설정 삭제와 이력 유지는 보존.',
    'settingsScheduleChangeWarning': '미제공 원터치 알람 설명 제거. 향후 10일 근무 알람 갱신과 이력 유지 보존.',
    'settingsResetScheduleConfirm': '미제공 공유 및 이전 한국어 이용 예외 설명 제거. 근무표·팀표·알람·이력·생성 기록 초기화는 명시.',
    'privacyIntro': '첫 출시의 제공 기능, 로컬 파일, Google 통계·광고만 설명. 이전 한국어 데이터 문장 제거.',
    'privacyNoCollectionBody': '개인 일정·수면·공유·언어 전환 기록 문단 제거. 실제 제공 데이터와 진단 항목·수동 전송은 보존.',
    'privacyFirebaseTitle': '공유/한국 공휴일 설명 섹션을 앱 업데이트 섹션으로 분리.',
    'privacyFirebaseBody': '공유와 한국 공휴일은 외국어에서 제공/조회하지 않으므로 관련 설명 제거. 실제 사용하는 Google Play 업데이트 확인만 설명.',
    'privacyDataRetentionBody': '과거 한국어 기능 기록/공유 섹션 참조 제거. 비암호화·잔존 파일·백업 교체·Google 보관 설명 유지.',
    'helpBackupDataStorageBody': '미제공 기능의 과거 기록 설명 제거. 로컬 백업과 Google 서비스 개인정보처리방침 연결 유지.',
    'helpDiagnosticBody': '미제공 개인 일정·친구명 열거 제거. 메모·근무명 제외 및 진단 파일 수동 전송·삭제 설명 보존.',
    'helpCalendarLocaleBody': '미제공 공휴일/한국 음력 표시 설명 제거. 지역별 주 시작일·날짜 형식·빨간 일요일·근무시간 집계 의미 보존.',
    'helpCalendarHomeWidgetBody': '미제공 공휴일·음력·한국어판 비교 설명 제거. 실제 제공 달력 위젯 사용법과 지역별 요일 순서 보존.',
}

def xml_messages(text):
    root = ET.fromstring(text)
    result = {e.attrib['name']: ''.join(e.itertext()) for e in root.findall('string')}
    for array in root.findall('string-array'):
        for i, item in enumerate(array.findall('item')):
            result[f"{array.attrib['name']}[{i}]"] = ''.join(item.itertext())
    return result

def write_csv(name, rows):
    with (OUT / name).open('w', encoding='utf-8-sig', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

def main():
    snapshots = json.loads((OUT / '시작_리소스.json').read_text(encoding='utf8'))
    resources = {}
    manifest = {}
    for name, saved in snapshots.items():
        path = ROOT / name
        current = path.read_text(encoding='utf8')
        lang = next(code for code in LANGS.values() if f'app_{code}.' in name or f'values-{code}' in name) if 'values\\strings' not in name else 'en'
        kind = 'arb' if name.endswith('.arb') else 'android'
        read = json.loads if kind == 'arb' else xml_messages
        resources[(kind, lang)] = (read(saved['text']), read(current))
        manifest[name] = {'start_sha256': saved['sha256'], 'final_sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

    # Rebuild reference evidence from source, excluding generated localization code.
    sources = [(p.relative_to(ROOT).as_posix(), p.read_text(encoding='utf8').splitlines())
               for p in (ROOT / 'lib').rglob('*.dart') if 'generated' not in p.parts]
    references = {}
    en = resources[('arb', 'en')][1]
    for path, lines in sources:
        for i, line in enumerate(lines, 1):
            for token in re.findall(r'\b[A-Za-z][A-Za-z0-9]+\b', line):
                if token in en and not token.startswith('@'):
                    references.setdefault(token, set()).add(f'{path}:{i}')

    with (PRIOR / '전수_검토원장.csv').open(encoding='utf-8-sig') as f:
        previous = list(csv.DictReader(f))
    rows = []
    for old in previous:
        region, kind, key, card = (old[k] for k in ['언어·지역', '리소스', '키', '카드'])
        lang = LANGS[region]
        initial, current = resources[(kind, lang)]
        before, after = initial[key], current[key]
        assert before == old['채택 문구'], (lang, key)
        changed = before != after
        decision, reason, proof = 'KEEP-' + card, KEEP[card], old['코드 사용 위치']
        difference = '2차 채택 문구 유지. 독립 후보와 의미카드 재대조 후 기능 의미를 바꿀 근거 없음.'
        if changed:
            if key in SCOPE_KEYS:
                decision, reason = 'T07', SCOPE_KEYS[key]
                proof = 'lib/main.dart; lib/l10n/l10n_extensions.dart; lib/screens/help_screen.dart; lib/screens/settings_tab.dart; lib/services/holiday_sync_service.dart; lib/services/friend_sync_service.dart; lib/services/update_service.dart'
                difference = '1·2차의 한국어 기능/이전 데이터 안내 유지 결정을 사용자 최종 지시(해외 첫 출시·제공 기능만·데이터별 예외 없음)로 변경. 한국어 문구와 데이터 저장 동작은 변경하지 않음.'
            else:
                decision, reason, proof = DECISIONS[key]
                difference = '1·2차 유지 판단을 실제 호출 조건/동작에 따라 보완. 표현 취향 변경 아님.'
        if key == 'helpSleepWidgetBody':
            reason = KEEP['C13']
            decision = 'T01-유지'
            difference = '숨김 문구의 번역 보완보다 비노출을 우선한다는 사용자 지시. 향후 제공 시 누락 문단 검토 필요.'
        refs = '; '.join(sorted(references.get(key, []))) if kind == 'arb' else old['코드 사용 위치']
        rows.append({
            '검토 ID': f'R3-20261005-{kind}-{lang}-{key}', '날짜': '2026-10-05',
            '언어·지역': region, '리소스': kind, '키': key, '카드': card,
            '이전 검토 ID': old['검토 ID'], '이전 결정 ID': old['결정 ID'],
            '결정 ID': decision, '한국어 원문': old['한국어 원문'],
            '변경 전': before, '제안 및 채택 문구': after,
            '결정': '채택' if changed else '유지', '채택 또는 유지 이유': reason,
            '출처': '1차 의미카드 ' + card + '; ' + proof,
            '기존 결정과 차이': difference,
            '현재 호출 위치': refs or '현재 lib 비생성 소스에 키 참조 없음; 런타임 실측과 구별',
            '3차 텍스트 독해': '완료', '노출 검증': '미제공_기능과_노출검증.txt 및 노출_검토원장.csv 참조; 실기기 미수행',
            '자동검증': '검토결과.txt 및 실행 로그 참조', '레이아웃': '요청에 따라 미수행',
            '반영': '미커밋 작업 트리',
        })
    assert len(rows) == 2944
    write_csv('전수_검토원장.csv', rows)
    changed = [r for r in rows if r['결정'] == '채택']
    write_csv('문구_변경원장.csv', changed)
    (OUT / '채택_변경.json').write_text(json.dumps(changed, ensure_ascii=False, indent=2), encoding='utf8')
    unused = [{'키': k, '정적 판정': '현재 lib 비생성 소스 참조 없음', '실기기': '미수행'}
              for k in en if not k.startswith('@') and k not in references]
    write_csv('직접호출_미발견.csv', unused)
    candidates = set(json.loads((OUT / '노출_검색키.json').read_text(encoding='utf8')))
    candidates.update(SCOPE_KEYS)
    candidates.update(k for k in en if re.match(r'(help(Sleep|Condition|Friend|OneTap|ScheduleTab)|friend|customAlarm|oneTap|schedule(New|Edit|Delete|Notify)|theme(EventChip|InitialBadge|Underline|Editorial))', k))
    exposures = []
    for key in sorted(candidates):
        if key not in en or key.startswith('@'):
            continue
        if key in SCOPE_KEYS:
            outcome, evidence = '제공 기능만 남기도록 수정', SCOPE_KEYS[key]
        elif key == 'settingsResetScheduleSharingFailed':
            outcome, evidence = '한국어에서만 경고 표시', 'settings_tab.dart: resetSchedule 결과 분기에 usesKoreanFeatures 추가'
        elif not references.get(key):
            outcome, evidence = '현재 비생성 Dart 참조 없음', '전수 키 참조 검색; 실제 화면 통과로 계산하지 않음'
        elif re.match(r'(help(Sleep|Condition|Friend|OneTap|ScheduleTab)|helpTroubleshootFriend)', key):
            outcome, evidence = '외국어 도움말 제외', 'help_screen.dart: section/topic KoreanOnly 필터 및 상세 재검사; 검색 경유도 플래그 전달'
        elif key.startswith(('friend', 'navFriend', 'settingsFriend', 'calendarFriend')):
            outcome, evidence = '한국어 전용 앱 경로', 'calendar_tab.dart 진입 차단; friend_list/my_share_code/friend_calendar_view 언어 재검사. web_main의 공개 웹 뷰어는 앱 제공 기능과 구분'
        elif key.startswith(('customAlarm', 'oneTap')):
            outcome, evidence = '한국어 전용 생성/편집 경로', 'calendar_tab.dart 원터치 진입·패널·날짜별 목록 차단. 신규 외국어 설치에서 이 종류 알람 생성 경로 없음; 이관 예외 UI 추가 안 함'
        elif key.startswith(('schedule', 'navSchedule', 'settingsScheduleTab', 'onboardingScheduleTab')):
            outcome, evidence = '한국어 전용 개인 일정 경로', 'main.dart 탭/알림 진입 차단; settings_tab 재활성화 차단; 튜토리얼 언어 재검사; native scheduler/receiver 차단'
        elif key.startswith('theme'):
            outcome, evidence = '외국어 테마 선택 대상에서 제외', 'calendar_theme.dart 6종만; picker preview는 IgnorePointer로 미제공 디자인 이동 불가'
        else:
            outcome, evidence = '제공 기능 문맥 유지', '키워드 일치만으로 삭제하지 않음. 알람/메모/복원/권한/업데이트의 실제 문맥 독해; 미제공 기능 사용 유도 없음'
        exposures.append({'키': key, '네 언어 공통 판정': outcome, '근거·원인·조치': evidence,
                          '현재 호출 위치': '; '.join(sorted(references.get(key, []))),
                          '실기기/레이아웃': '미수행; 자동검사와 정적 판정만'})
    write_csv('노출_검토원장.csv', exposures)
    summary = {'baseline_commit': '080ca5913dbe9787c15fa7d60baca95b805075ed',
               'reviewed': len(rows), 'changed': len(changed), 'kept': len(rows)-len(changed),
               'changed_by_language': dict(Counter(r['언어·지역'] for r in changed)),
               'exposure_key_count': len(exposures), 'no_direct_reference_count': len(unused),
               'resources': manifest, 'layout_tested': False, 'physical_device_tested': False}
    (OUT / '검증_명세.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf8')
    print(json.dumps({k: v for k, v in summary.items() if k != 'resources'}, ensure_ascii=False))

if __name__ == '__main__':
    main()
