"""Build/check the offline game font; fontTools is a development-only dependency."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

PACKAGE = Path(__file__).resolve().parents[1]
REPO = PACKAGE.parents[1]
sys.path.insert(0, str(PACKAGE / '.dart_tool/font_subset_tools'))
from fontTools import subset
from fontTools.ttLib import TTFont

SOURCE = PACKAGE / 'assets/fonts/NotoSansKR.ttf'
OUTPUT = PACKAGE / 'assets/fonts/GameSansSubset.ttf'
SOURCE_SHA = '194018e6b2b293a7964f037b25c0249ce1418bc9ab3c971060a03aa57861e252'


def content_codepoints():
    # Conservatively include all source characters, including comments, rather
    # than depending on a Dart string parser. JSON is decoded before scanning.
    points = set(range(0x20, 0x7F))
    files = []
    for folder in [PACKAGE / 'lib', REPO / 'packages/sync_path_core/lib',
                   REPO / 'examples/sync_path_lab/lib']:
        files.extend(sorted(folder.rglob('*.dart')))
    files.extend(sorted((REPO / 'examples/sync_path_lab/assets').glob('*.json')))
    for path in files:
        text = path.read_text(encoding='utf-8')
        if path.suffix == '.json':
            text = json.dumps(json.loads(text), ensure_ascii=False)
        points.update(ord(c) for c in text if c.isprintable())
        points.update(int(value, 16) for value in
                      re.findall(r'\\u(?:\{([0-9a-fA-F]+)\}|([0-9a-fA-F]{4}))', text)
                      for value in value if value)
    return points


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != SOURCE_SHA:
        raise SystemExit('Original font changed; review provenance before regenerating.')
    with TTFont(SOURCE, recalcTimestamp=False) as original:
        original_cmap = original.getBestCmap()
        requested = content_codepoints()
        # Preserve existing fallback for characters absent in the full font.
        required = requested & original_cmap.keys()
        fallback = sorted(requested - original_cmap.keys())
        if not args.check:
            options = subset.Options()
            options.name_IDs = ['*']  # Keep copyright/license and variable weights.
            options.name_legacy = True
            options.name_languages = ['*']
            options.notdef_outline = True
            worker = subset.Subsetter(options=options)
            worker.populate(unicodes=required)
            worker.subset(original)
            names = {1: 'Sync Path Game Sans', 3: 'SyncPathGameSans-Subset-v1',
                     4: 'Sync Path Game Sans', 6: 'SyncPathGameSans',
                     16: 'Sync Path Game Sans', 25: 'SyncPathGameSans'}
            for record in original['name'].names:
                if record.nameID in names:
                    record.string = names[record.nameID].encode(record.getEncoding())
            original.save(OUTPUT)
    with TTFont(OUTPUT, recalcTimestamp=False) as result:
        missing = required - result.getBestCmap().keys()
        if missing:
            raise SystemExit('Font lacks new content; regenerate: ' +
                             ', '.join(f'U+{cp:04X}' for cp in sorted(missing)))
        weights = [dict(tag=axis.axisTag, minimum=axis.minValue,
                        maximum=axis.maxValue) for axis in result['fvar'].axes]
    assets = [OUTPUT,
              REPO / 'examples/sync_path_lab/assets/pilot_levels.json',
              *sorted((REPO / 'examples/sync_path_lab/assets/art').glob('*.webp')),
              *sorted((REPO / 'examples/sync_path_lab/android/app/src/main/assets/sync_paths_audio').glob('*.wav'))]
    total = sum(path.stat().st_size for path in assets)
    if total >= 500_000:
        raise SystemExit(f'Game asset budget exceeded: {total} >= 500000 bytes')
    report = dict(sourceBytes=SOURCE.stat().st_size, fontBytes=OUTPUT.stat().st_size,
                  requiredCodepoints=len(required), missingCodepoints=[],
                  existingFallbackCodepoints=[f'U+{cp:04X}' for cp in fallback],
                  fontAxes=weights, assetBytes=total, assetBudgetBytes=500_000,
                  compiledCodeIncluded=False,
                  assets=[dict(path=str(path.relative_to(REPO)), bytes=path.stat().st_size)
                          for path in assets],
                  fontSha256=hashlib.sha256(OUTPUT.read_bytes()).hexdigest())
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(rendered + '\n', encoding='utf-8')
    print(rendered)


if __name__ == '__main__':
    main()
