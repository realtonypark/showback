#!/usr/bin/env python3
"""Measure exported narration placement against run.json (QA: ffmpeg, NumPy, SciPy)."""
import json
from pathlib import Path
import subprocess
import sys
import numpy as np
from scipy.signal import correlate

root = Path(sys.argv[1]).resolve()
state = json.loads((root / 'run.json').read_text())
def samples(path):
    result = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(path), '-vn', '-ac', '1', '-ar', '24000', '-f', 'f32le', '-'], capture_output=True, check=True)
    return np.frombuffer(result.stdout, dtype='<f4')
output = samples(root / 'demo.mp4')
for segment in state['narration']:
    source = samples(root / segment['path'])
    length = min(len(source), round(segment['duration'] * 24000))
    source = source[:length]
    expected = round(segment['start'] * 24000)
    low = max(0, expected-4800)
    region = output[low:min(len(output), expected+length+4800)]
    assert len(region) >= length, 'Narration was truncated'
    scores = correlate(region, source, mode='valid', method='fft')
    actual = low + int(np.argmax(scores))
    delta = (actual-expected)/24000
    assert abs(delta) <= .1, (segment['path'], 'Audio/video discrepancy exceeds 100ms', delta)
    aligned = output[actual:actual+length]
    similarity = np.corrcoef(source, aligned)[0,1]
    assert similarity > .95, ('Narration differs/truncated', similarity)
    print(f"{segment['path']}: exported offset {delta*1000:.2f} ms, waveform correlation {similarity:.4f}")
