"""Measure the actual top-level RTL PCM dump, without synthesizing audio."""
from pathlib import Path
import csv, json, math
p = Path(__file__).resolve().parents[1]
out = p / 'results/rp108'
rows = [tuple(map(int, r)) for r in csv.reader((out / 'top_pcm.csv').open())]
info = {'source': str(out / 'top_pcm.csv'), 'frames': len(rows), 'channels': {}}
for i, name in [(1, 'left'), (2, 'right')]:
    samples = [r[i] for r in rows]
    info['channels'][name] = dict(min=min(samples), max=max(samples),
        peak=max(map(abs, samples)), rms=math.sqrt(sum(s*s for s in samples)/len(samples)),
        clipped_frames=sum(s in (-32768, 32767) for s in samples))
info['note'] = 'Actual RTL stereo PCM; accelerated peripheral/control test, not a listening sample or exhaustive 32-note clipping test.'
(out / 'pcm_analysis.json').write_text(json.dumps(info, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(info, ensure_ascii=False, indent=2))
