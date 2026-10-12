"""Check resource structure; this does not judge translation or visual quality."""
import argparse
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path


def audit(root):
    languages = ['ko', 'en', 'pt', 'de', 'hi']
    arbs = {lang: json.loads((root / f'lib/l10n/app_{lang}.arb').read_text('utf-8'))
            for lang in languages}
    xmls = {}
    for lang in languages:
        folder = 'values' if lang == 'en' else f'values-{lang}'
        tree = ET.parse(root / f'android/app/src/main/res/{folder}/strings.xml')
        entries = {}
        for node in tree.getroot():
            name = node.attrib['name']
            assert name not in entries, (lang, 'duplicate XML key', name)
            if node.tag == 'string-array':
                for index, item in enumerate(node):
                    entries[f'{name}[{index}]'] = item.text or ''
            else:
                entries[name] = node.text or ''
        xmls[lang] = entries
    keys = {key for key in arbs['ko'] if not key.startswith('@')}
    korean_only = json.loads((root / 'lib/l10n/korean_only/messages_ko.json').read_text('utf-8'))
    scoped_keys = {key for key in korean_only if not key.startswith('@')}
    args = lambda text: set(re.findall(r'\{(\w+)[},]', text))
    formats = lambda text: sorted(re.findall(r'%(?:\d+\$)?[sdif]', text))
    report = {'errors': [], 'languages': {}, 'limits':
              'Structure only. ICU generation, semantic review and device layout review are separate.'}
    for flavor, expected in [('dev', 'ShiftBell (Test)'), ('prod', 'ShiftBell')]:
        for lang in ['en', 'pt', 'de', 'hi']:
            path = root / f'android/app/src/{flavor}/res/values-{lang}/strings.xml'
            if not path.exists() or ET.parse(path).getroot().find("string[@name='app_name']").text != expected:
                report['errors'].append([flavor, lang, 'explicit foreign app name missing/incorrect'])
    native_scoped = {n.attrib['name']: n.text for n in ET.parse(root / 'android/app/src/main/res/values/korean_only.xml').getroot()}
    if set(native_scoped) & set(xmls['en']):
        report['errors'].append(['native scoped key overlaps common scope'])
    for path in (root / 'lib/l10n/generated').glob('*.dart'):
        code = path.read_text('utf-8')
        for key in scoped_keys:
            if re.search(r'\bString\s+(?:get\s+)?'+re.escape(key)+r'\b', code):
                report['errors'].append([str(path.relative_to(root)), key, 'scoped API leaked into common generation'])
    missing = root / 'build/l10n_untranslated.json'
    if not missing.exists() or json.loads(missing.read_text('utf-8')):
        report['errors'].append(['generated untranslated report missing/nonempty'])
    snapshot = root / 'docs/next_version/후속재점검_2026-10-05/시작_자료.json'
    if snapshot.exists():
        original = json.loads(snapshot.read_text('utf-8'))['arbs']['ko']
        # Preserve the original review snapshot. Later user-requested edits have
        # an exact before/after ledger, rather than disabling copy preservation.
        changes = {}
        for copy_ledger in sorted((root / 'docs/next_version/evidence').glob('settings_copy_changes_*.json')):
            for key, change in json.loads(copy_ledger.read_text('utf-8'))['changes'].items():
                if key in changes:
                    if change['before'] != changes[key]['after']:
                        report['errors'].append([key, 'Korean copy follow-up ledger mismatch'])
                    changes[key] = {'before': changes[key]['before'], 'after': change['after']}
                else:
                    changes[key] = change
        for key, change in changes.items():
            if key not in scoped_keys or change['before'] != original.get(key) or change['after'] != korean_only.get(key):
                report['errors'].append([key, 'Korean copy change ledger mismatch'])
        for key in scoped_keys:
            if original.get(key) != korean_only[key] and key not in changes:
                report['errors'].append([key, 'Korean scoped text changed'])
        report['korean_preserved_scoped_messages'] = len(scoped_keys)
    report['native_korean_only_messages'] = len(native_scoped)
    for lang in languages[1:]:
        errors = report['errors']
        if scoped_keys & set(arbs[lang]):
            errors.append([lang, 'Korean-only key present in common translations'])
        if scoped_keys & keys:
            errors.append([lang, 'Korean-only key present in generation template'])
        if {k for k in arbs[lang] if not k.startswith('@')} != keys:
            errors.append([lang, 'ARB key mismatch'])
        if set(xmls[lang]) != set(xmls['ko']):
            errors.append([lang, 'XML key mismatch'])
        for key in keys:
            value = arbs[lang].get(key, '')
            if not value.strip() or re.search('[가-힣\ufffd]', value):
                errors.append([lang, key, 'empty/Korean/replacement character'])
            if args(value) != args(arbs['ko'][key]):
                errors.append([lang, key, 'ICU arguments differ'])
        for key, original in xmls['ko'].items():
            value = xmls[lang].get(key, '')
            if not value.strip() or re.search('[가-힣\ufffd]', value):
                errors.append([lang, key, 'empty/Korean/replacement character'])
            if formats(value) != formats(original):
                errors.append([lang, key, 'Android format arguments differ'])
        for native, flutter in [('widget_preview_day', 'shiftDay'),
                                ('widget_preview_night', 'shiftNight'),
                                ('widget_preview_off', 'shiftOff')]:
            if xmls[lang][native] != arbs[lang][flutter]:
                errors.append([lang, native, flutter, 'shared term differs'])
        weekdays = [xmls[lang][f'widget_weekday_{i}'] for i in range(7)]
        if weekdays != [xmls[lang][f'widget_weekday_labels[{i}]'] for i in range(7)]:
            errors.append([lang, 'weekday array differs from weekday strings'])
        report['languages'][lang] = {
            'arb_messages': len(keys), 'android_strings': len(xmls[lang]) - 7,
            'android_weekday_items': 7,
            'same_as_english_for_manual_review': [] if lang == 'en' else
            [k for k in keys if arbs[lang][k] == arbs['en'][k]],
        }
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default='build/semantic_review_2026-10-05/resource_audit.json')
    options = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    result = audit(root)
    destination = root / options.output
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, ensure_ascii=False, indent=2), 'utf-8')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(bool(result['errors']))
