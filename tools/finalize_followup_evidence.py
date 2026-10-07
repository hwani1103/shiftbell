"""Archive completed checks and build metadata; never manufacture device PASS."""
from pathlib import Path
import csv
import hashlib
import json
import re
import shutil
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/next_version/후속재점검_2026-10-05'

def read_log(path):
    data = path.read_bytes()
    return data.decode('utf-16' if data.startswith((b'\xff\xfe', b'\xfe\xff')) else 'utf-8', errors='replace')

critical = read_log(ROOT / 'build/followup_critical_final.log')
assert '+101: All tests passed!' in critical
assert 'P0 automated checks passed.' in critical
analysis = read_log(ROOT / 'build/followup_analyze_final.log')
assert re.search(r'\d+ issues found\.', analysis), 'Analysis is unfinished'
counts = {level: len(re.findall(r'^\s*' + level + r' - ', analysis, re.M))
          for level in ['error', 'warning', 'info']}
assert counts['error'] == counts['warning'] == 0, counts
audit = json.loads((ROOT / 'build/critical_resource_audit.json').read_text('utf-8'))
assert not audit['errors']
assert json.loads((ROOT / 'build/l10n_untranslated.json').read_text('utf-8')) == {}
native = {}
for name in ['PermissionSettingsTest', 'ReleaseLanguagesTest']:
    path = ROOT / f'build/app/test-results/testDevDebugUnitTest/TEST-com.hwani1103.shiftbell.{name}.xml'
    suite = ET.parse(path).getroot()
    assert suite.attrib['failures'] == suite.attrib['errors'] == '0'
    assert suite.attrib.get('skipped', '0') == '0'
    native[name] = int(suite.attrib['tests'])
assert sum(native.values()) == 12
artifacts = {}
for relative in ['build/app/outputs/flutter-apk/app-dev-debug.apk',
                 'build/app/outputs/flutter-apk/app-dev-release.apk', 'build/web/main.dart.js']:
    p = ROOT / relative
    artifacts[relative] = {'bytes': p.stat().st_size,
        'modified_utc': datetime.fromtimestamp(p.stat().st_mtime, timezone.utc).isoformat(),
        'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
logs = OUT / '검증로그'
logs.mkdir(exist_ok=True)
for name in ['followup_critical_final.log', 'followup_analyze_final.log',
             'followup_native_final.log', 'followup_prod_release.log',
             'followup_dev_release.log', 'followup_diff_check.log']:
    shutil.copyfile(ROOT / 'build' / name, logs / name)
for name in native:
    p = ROOT / f'build/app/test-results/testDevDebugUnitTest/TEST-com.hwani1103.shiftbell.{name}.xml'
    shutil.copyfile(p, logs / p.name)
shutil.copyfile(ROOT / 'build/critical_resource_audit.json', OUT / '리소스_자동검사.json')
verification = {
    'date': '2026-10-05', 'flutter_functional_tests': {'PASS': 101},
    'native_robolectric_tests': native, 'dart_analysis_lib_test': counts,
    'resource_errors': 0, 'generated_untranslated': {},
    'builds': {'dev_debug_apk': 'PASS', 'dev_release_apk_optimized': 'PASS',
              'public_web_javascript': 'PASS',
              'prod_release': 'BLOCKED_BY_EXISTING_CHECK_PROD_AD_IDS_MISSING_BANNER_ID'},
    'artifacts': artifacts,
    'device_locked_alarm_oem_process_restart_launcher_widget': 'NOT_RUN',
    'live_firestore_public_web_server_network': 'NOT_RUN',
    'localized_oem_setting_names_native_speaker_review': 'NOT_RUN',
    'layout': 'EXCLUDED; initial accidental legacy reset layout/capture test execution recorded in review, not counted as verification',
    'web_wasm_and_cupertino_font_warning': 'JS build passed; Wasm/actual icon display not verified',
    'scope': 'Selected functional regression suite; not all repository tests. Prior AH/AJ observations are not current device PASS.',
    'evidence_logs': '검증로그/',
}
(OUT / '검증_명세.json').write_text(json.dumps(verification, ensure_ascii=False, indent=2), 'utf-8')
for relative in ['docs/next_version/후속재점검_2026-10-05/검토결과.txt',
                 'docs/next_version/후속재점검_2026-10-05/다음_시작점.txt',
                 'docs/next_version/다국어_제작_검증현황.txt',
                 'docs/next_version/교대시계_최신문서.txt']:
    p = ROOT / relative
    s = p.read_text('utf-8').replace('info 654', f"info {counts['info']}")
    s = s.replace('기존 스타일 info 654건', f"기존 스타일 info {counts['info']}건")
    if relative.endswith('검토결과.txt'):
        s = s.replace('Android dev release 최적화 빌드 결과는 검증_명세.json/빌드 로그를 우선한다.',
                      'Android dev release 최적화 빌드도 마지막 수정 후 PASS. 최종 APK/웹 산출물 해시와 로그는 검증_명세.json을 참조한다.')
    p.write_text(s, 'utf-8')
hashfile = OUT / '최종_소스리소스_해시.json'
hashes = json.loads(hashfile.read_text('utf-8'))
for relative in ['AGENTS.md', 'tools/finalize_followup_evidence.py']:
    hashes[relative] = hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()
hashfile.write_text(json.dumps(hashes, ensure_ascii=False, indent=2), 'utf-8')
for relative, sha in hashes.items():
    assert hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() == sha, relative
with (OUT / '하드코딩_도달판정.csv').open(encoding='utf-8-sig') as f:
    rows = list(csv.DictReader(f))
for row in rows:
    row['보존·수정 판정'] = row['보존·수정 판정'].replace('原本', '원본')
with (OUT / '하드코딩_도달판정.csv').open('w', encoding='utf-8-sig', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
print(json.dumps({'flutter': 101, 'native': native, 'analysis': counts,
                  'builds': verification['builds'], 'source_hashes_checked': len(hashes)}, ensure_ascii=False))
