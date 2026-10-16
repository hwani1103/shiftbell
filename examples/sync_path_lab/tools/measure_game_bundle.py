"""Measure real packaged game assets; never count debug VM/kernel as game AOT."""
import hashlib
import json
import wave
import zipfile
from pathlib import Path

HOST = Path(__file__).resolve().parents[1]
REPO = HOST.parents[1]
OUTPUT = REPO / 'docs/UI 完성도 개선/GAME-13_검증_2026-10-15'
OUTPUT.mkdir(parents=True, exist_ok=True)
bundle = HOST / 'build/app/outputs/bundle/devDebug/app-dev-debug.aab'
apk = HOST / 'artifacts/game13/app-dev-debug.apk'
suffixes = ['assets/pilot_levels.json', 'assets/pilot_copy.json',
            'assets/art/sync_paths_splash.webp',
            'packages/sync_path_ui/assets/fonts/GameSansSubset.ttf']
with zipfile.ZipFile(bundle) as archive:
    rows = [dict(path=i.filename, rawBytes=i.file_size, storedBytes=i.compress_size)
            for i in archive.infolist()
            if any(i.filename.endswith(s) for s in suffixes)
            or '/sync_paths_audio/' in i.filename]
    assert len(rows) == 10, rows
    for name in ['select', 'route', 'undo', 'start', 'failure', 'clear']:
        path = HOST / f'android/app/src/main/assets/sync_paths_audio/{name}.wav'
        found = next(i for i in archive.namelist() if i.endswith(f'sync_paths_audio/{name}.wav'))
        assert archive.read(found) == path.read_bytes()
        with wave.open(str(path)) as wav:
            assert (wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) == (1, 2, 22050)
            assert wav.getnframes() / wav.getframerate() < 1
with zipfile.ZipFile(apk) as archive:
    for name in ['select', 'route', 'undo', 'start', 'failure', 'clear']:
        assert archive.read(f'assets/sync_paths_audio/{name}.wav') == (
            HOST / f'android/app/src/main/assets/sync_paths_audio/{name}.wav').read_bytes()
result = dict(
    buildType='devDebug (not a release size measurement)',
    bundle=str(bundle.relative_to(REPO)),
    apkSha256=hashlib.sha256(apk.read_bytes()).hexdigest(),
    gameAssetsRawBytes=sum(r['rawBytes'] for r in rows),
    gameAssetsStoredBytes=sum(r['storedBytes'] for r in rows),
    soundRawBytes=sum(r['rawBytes'] for r in rows if '/sync_paths_audio/' in r['path']),
    soundStoredBytes=sum(r['storedBytes'] for r in rows if '/sync_paths_audio/' in r['path']),
    excluded='Shared Flutter engine/framework, Material icons, AOT code, native DEX and bundle metadata. Release AOT delta requires integrated before/after release builds.',
    assets=rows,
)
(OUTPUT / 'bundle-size.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(result, ensure_ascii=False, indent=2))
