"""Evidence helper for the 2026-10-06 review; never a semantic auto-approval."""
import csv
import hashlib
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/next_version/최종튜닝_2026-10-06'


def resources(lang):
    arb = json.loads((ROOT / f'lib/l10n/app_{lang}.arb').read_text('utf-8'))
    result = {('arb', k): v for k, v in arb.items() if not k.startswith('@')}
    folder = 'values' if lang == 'en' else f'values-{lang}'
    for node in ET.parse(ROOT / f'android/app/src/main/res/{folder}/strings.xml').getroot():
        key = node.attrib['name']
        if node.tag == 'string-array':
            for i, item in enumerate(node):
                result['android', f'{key}[{i}]'] = item.text or ''
        else:
            result['android', key] = node.text or ''
    return result


def snapshot():
    OUT.mkdir(exist_ok=True)
    paths = [p for base in ['lib', 'android/app/src', 'test', 'tools', 'docs/next_version']
             for p in (ROOT / base).rglob('*') if p.is_file()
             and p.suffix in {'.dart', '.kt', '.xml', '.arb', '.json', '.csv', '.txt', '.ps1', '.py'}
             and OUT not in p.parents and '__pycache__' not in p.parts]
    data = {'sha256': {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},
            'resources': {lang: [{'resource': r, 'key': k, 'text': v} for (r, k), v in resources(lang).items()]
                          for lang in ['ko', 'pt', 'de', 'en', 'hi']}}
    dest = OUT / '시작_자료.json'
    if dest.exists():
        raise SystemExit('Snapshot already exists; refusing to overwrite')
    dest.write_text(json.dumps(data, ensure_ascii=False, indent=2), 'utf-8')
    (OUT / '시작_git_status.txt').write_bytes(subprocess.run(['git', 'status', '--short'], cwd=ROOT, capture_output=True).stdout)
    print('Snapshot:', len(paths), 'files;', len(resources('pt')), 'items/language')


if __name__ == '__main__':
    if sys.argv[1] == 'snapshot':
        snapshot()
    elif sys.argv[1] == 'read':
        lang, start, count = sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
        for i, ((res, key), value) in enumerate(list(resources(lang).items())[start:start+count], start):
            print(f'{i} {res}:{key} | ' + value.replace('\n', ' / '))
    elif sys.argv[1] == 'history':
        for folder in ['의미검토_1차_2026-10-05', '자연스러움검토_2차_2026-10-05', '독립최종검토_3차_2026-10-05', '후속재점검_2026-10-05']:
            filename = '후속_문구원장.csv' if folder.startswith('후속') else '문구_변경원장.csv'
            rows = list(csv.DictReader((ROOT / 'docs/next_version' / folder / filename).open(encoding='utf-8-sig', newline='')))
            print(folder, len(rows))
            seen = set()
            for row in rows:
                if len(sys.argv) > 2 and sys.argv[2] not in row['키']:
                    continue
                reason = row.get('뜻·결정 근거', row.get('뜻·채택 또는 유지 이유', row.get('채택 또는 유지 이유', row.get('삭제·분기·유지 이유', ''))))
                if not reason:
                    reason = str(row)
                token = reason
                if token in seen:
                    continue
                seen.add(token)
                print(row['키'], '|', reason)
    elif sys.argv[1] == 'scan':
        pattern = r'''(?:Text|TextSpan)\(\s*(?:text:\s*)?['"][A-Za-z가-힣]|(?:tooltip|hintText|labelText):\s*['"][A-Za-z가-힣]'''
        result = subprocess.run(['rg', '-n', pattern, 'lib', '-g', '*.dart', '-g', '!**/generated/**', '-g', '!korean_only_copy.dart'], cwd=ROOT, capture_output=True)
        (OUT/'하드코딩_UI검색.txt').write_bytes(result.stdout)
        print(result.stdout.decode('utf-8'))
        old = json.loads((ROOT/'docs/next_version/후속재점검_2026-10-05/최종_소스리소스_해시.json').read_text('utf-8'))
        changed = [p for p, digest in old.items() if (ROOT/p).exists() and hashlib.sha256((ROOT/p).read_bytes()).hexdigest() != digest]
        print('Different from prior raw-byte hashes:', changed)
