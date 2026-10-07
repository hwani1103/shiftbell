"""Freeze successful final check evidence; refuses to label unfinished builds PASS."""
import hashlib
import json
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from review_release_20261006 import ROOT, OUT

def read_log(path):
    raw = path.read_bytes()
    return raw.decode('utf-16') if raw.startswith(b'\xff\xfe') else raw.decode('utf-8-sig')

log = ROOT/'build/final_tuning_verified_20261006.log'
text = read_log(log)
assert 'P0 automated checks passed.' in text, 'Final P0 build still incomplete/failed'
assert 'Built build\\app\\outputs\\flutter-apk\\app-dev-debug.apk' in text
assert 'Built build\\app\\outputs\\flutter-apk\\app-dev-release.apk' in text
assert 'Built build\\web' in text
flutter = int(re.findall(r'\+(\d+): All tests passed!', text)[-1])
audit = json.loads((ROOT/'build/critical_resource_audit.json').read_text('utf-8'))
assert not audit['errors']
assert json.loads((ROOT/'build/l10n_untranslated.json').read_text('utf-8')) == {}
native = {}
test_paths = []
for name in ['PermissionSettingsTest', 'ReleaseLanguagesTest', 'NotificationLocaleTest', 'G1RingRoundTest', 'CoverAlarmNotificationTest']:
    path = ROOT/f'build/app/test-results/testDevDebugUnitTest/TEST-com.hwani1103.shiftbell.{name}.xml'
    node = ET.parse(path).getroot()
    assert node.attrib['failures'] == '0' and node.attrib['errors'] == '0', name
    native[name] = int(node.attrib['tests'])
    test_paths.append(path)
analysis = read_log(ROOT/'build/final_tuning_analyze.log')
levels = Counter(line.split('|')[0] for line in analysis.splitlines() if '|' in line)
assert levels['ERROR'] == 0 and levels['WARNING'] == 0
diff = subprocess.run(['git', '-c', 'core.safecrlf=false', 'diff', '--check'], cwd=ROOT, capture_output=True)
assert diff.returncode == 0, diff.stdout.decode('utf-8')
evidence = OUT/'검증로그'
evidence.mkdir(exist_ok=True)
for path in [log, ROOT/'build/final_tuning_critical_20261006.log', ROOT/'build/final_tuning_analyze.log',
             ROOT/'build/english_literal_candidates.txt', ROOT/'build/native_open_locale_targeted.log',
             ROOT/'build/final_tuning_before_accessibility_test_fix.log', ROOT/'build/final_tuning_before_parent_locale_fix.log',
             ROOT/'build/critical_resource_audit.json', ROOT/'build/l10n_untranslated.json', *test_paths]:
    shutil.copy2(path, evidence/path.name)
(evidence/'git_diff_check.txt').write_text('PASS exit=0\n'+diff.stdout.decode('utf-8')+diff.stderr.decode('utf-8'), 'utf-8')
hashes = {}
for base in ['lib', 'android/app/src', 'web', 'test', 'tools']:
    for path in (ROOT/base).rglob('*'):
        if path.is_file() and '__pycache__' not in path.parts and path.suffix in {'.dart','.kt','.xml','.arb','.json','.js','.cjs','.html','.py','.ps1'}:
            hashes[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
(OUT/'최종_소스리소스_해시.json').write_text(json.dumps(hashes, ensure_ascii=False, indent=2), 'utf-8')
artifacts = {}
for file in ['build/app/outputs/flutter-apk/app-dev-debug.apk', 'build/app/outputs/flutter-apk/app-dev-release.apk', 'build/web/main.dart.js', 'build/web/locale_bootstrap.js']:
    path = ROOT/file
    artifacts[file] = {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'bytes': path.stat().st_size,
                       'modified_utc': datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat()}
manifest = {'date':'2026-10-06', 'command':'powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_critical_release.ps1 -Build',
    'critical_exit_code':0, 'flutter_functional_tests':{'PASS':flutter}, 'native_robolectric_tests':native,
    'web_node_locale_cases':8, 'resource_errors':0, 'generated_untranslated':{},
    'dart_analysis_lib_test':{'error':levels['ERROR'],'warning':levels['WARNING'],'info':levels['INFO']},
    'git_diff_check':'PASS', 'builds':{'dev_debug_apk':'PASS','dev_release_apk_optimized':'PASS','public_web_javascript':'PASS',
        'prod_release':'NOT_RUN_THIS_SESSION; prior check blocked by missing real banner ID; dev is not prod'},
    'artifacts':artifacts, 'device_locked_alarm_oem_process_restart_launcher_widget':'NOT_RUN',
    'live_firestore_public_web_server_browser_install':'NOT_RUN','third_party_sdk_os_ui_language':'NOT_RUN',
    'native_speaker':'NOT_RUN','layout':'EXCLUDED_BY_USER; no layout/golden/screenshot tests',
    'adb_inventory':'Restricted invocation could not start ADB daemon; not evidence that no device exists. No installation performed.',
    'warnings':'Existing Gradle/Kotlin deprecations and Web Wasm dry-run/Cupertino font warnings; JS build success is not Wasm/icon visual PASS.',
    'scope':'Selected functional suite, not every repository test. Prior device observations are not current device PASS.',
    'evidence':'검증로그/; 최종_소스리소스_해시.json; 집계와_보존검사.json'}
(OUT/'검증_명세.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), 'utf-8')
summary = f'''2026-10-06 최종 튜닝 최신 판정 — 아래 과거 본문은 보존 기록
현재 시작점: 최종튜닝_2026-10-06/검토결과.txt, 다음_시작점.txt, 검증_명세.json.
외국어 2,204항목 독해·의미 대조: 7수정/12한국어 분리/2,185유지. common504/언어,
native37+요일7; 한국어 전용202+11=213 원문 보존. 과거 원장 상세 사유 연결.
공개 웹 이전 언어 오류·초기 metadata, 팀표 raw 예외, 열린 native 알람/기존 알림
언어 갱신을 보완. 기능 의미가 맞는 자연스러운 현지 표현은 유지.
필수 P0 -Build PASS: Flutter {flutter}, native {sum(native.values())}, 웹 locale8종,
dev debug/최적화 release APK와 공개 웹 JS 빌드. 분석 error0/warning0/info{levels['INFO']}.
실기기 권한·잠금알람/OEM/복수 locale·위젯/실서버·브라우저 설치/SDK·원어민은
NOT_RUN. 100% 출시 승인·절대 혼입0%라고 판정하지 않는다. 레이아웃 검사 제외.
prod release는 이번 미실행; 기존 실제 배너 ID 누락 차단 이력은 별도 확인 필요.

--- 이전 기록(보존) ---
'''
status = ROOT/'docs/next_version/다국어_제작_검증현황.txt'
if not status.read_text('utf-8-sig').startswith('2026-10-06 최종 튜닝 최신 판정'):
    status.write_bytes(summary.encode('utf-8')+status.read_bytes())
next_path = ROOT/'docs/next_version/후속재점검_2026-10-05/다음_시작점.txt'
prefix = '2026-10-06 후속 결과 연결: ../최종튜닝_2026-10-06/다음_시작점.txt 및 검토결과.txt를 우선한다.\n아래는 2026-10-05 종료 당시 시작점 원문 보존이다. 새 원장·미검증 범위는 최신 폴더 참조.\n\n'
if not next_path.read_text('utf-8-sig').startswith('2026-10-06 후속 결과 연결'):
    next_path.write_bytes(prefix.encode('utf-8')+next_path.read_bytes())
latest_doc = ROOT/'docs/next_version/교대시계_최신문서.txt'
heading = 'AO. 다국어 최종 튜닝·혼입 경로 보완 (2026-10-06)'
if heading not in latest_doc.read_text('utf-8-sig'):
    addition = f'\n\n{heading}\n- 현재 결과는 최종튜닝_2026-10-06/검토결과.txt 및 검증_명세.json. 문구7수정/12외국어 분리, 한국어213원문 보존.\n- 공개 웹 오류·metadata, 팀표 예외, 열린 native 제어/알림의 언어 변경 경로 보완. Flutter{flutter}/native{sum(native.values())}, P0 -Build 통과. APK 해시는 새 명세를 사용한다.\n- 실기기 P0/실서버/SDK·OS/현지인 감수는 NOT_RUN. 레이아웃 검사는 이번 범위에서 실행하지 않음. AN의 별도 검토는 그대로 보존.\n'
    with latest_doc.open('ab') as handle:
        handle.write(addition.encode('utf-8'))
print(json.dumps({'Flutter':flutter,'Native':native,'Analysis':dict(levels),'Builds':manifest['builds']}, ensure_ascii=False))
