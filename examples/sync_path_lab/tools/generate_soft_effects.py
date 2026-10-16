"""Original, deterministic sine-based effects; no external audio or licenses.

22.05kHz mono PCM, soft attack/release and no noise/high-frequency transients.
"""
import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'android/app/src/main/assets/sync_paths_audio'
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050
# (start time, duration, frequency, relative gain)
SOUNDS = {
    'select': [(0, .18, 392, .8), (.025, .16, 494, .22)],
    'route': [(0, .14, 330, .7)],
    'undo': [(0, .19, 330, .6), (.07, .20, 262, .55)],
    'start': [(0, .22, 262, .5), (.10, .23, 330, .5), (.20, .28, 392, .5)],
    'failure': [(0, .32, 220, .6), (.13, .36, 165, .5)],
    'clear': [(0, .42, 262, .45), (.12, .45, 330, .4),
              (.24, .48, 392, .4), (.36, .55, 523, .35)],
}
for name, notes in SOUNDS.items():
    count = math.ceil(max(start + duration for start, duration, _, _ in notes) * RATE)
    samples = []
    for i in range(count):
        t = i / RATE
        sample = 0.0
        for start, duration, frequency, gain in notes:
            local = t - start
            if 0 <= local < duration:
                # Smooth zero-slope fade at both ends prevents clicks.
                attack = .025
                envelope = (math.sin(min(local / attack, 1) * math.pi / 2) ** 2
                            * math.cos(local / duration * math.pi / 2) ** 2)
                sample += gain * envelope * math.sin(2 * math.pi * frequency * local)
        samples.append(round(sample * .23 * 32767))
    assert max(map(abs, samples)) < 32767
    with wave.open(str(OUT / f'{name}.wav'), 'wb') as file:
        file.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        file.writeframes(struct.pack(f'<{len(samples)}h', *samples))
    print(name, count / RATE, (OUT / f'{name}.wav').stat().st_size)
