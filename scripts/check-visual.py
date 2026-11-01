#!/usr/bin/env python3
"""Measure a controlled UI transition, move alignment, and window-capture isolation.

Requires build-fixtures.sh apps on a virtual display; native fixture --events must
point to the absolute path in SHOWBACK_FIXTURE_EVENTS. Requires ffmpeg and Pillow.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from PIL import Image, ImageChops, ImageStat

binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else '.build/debug/showback').resolve())
desktop = str(Path(os.environ['SHOWBACK_ASSETS']) / 'bin/agent-desktop')
events = Path(os.environ['SHOWBACK_FIXTURE_EVENTS'])
root = Path(sys.argv[2] if len(sys.argv) > 2 else '.local/visual.showback').resolve()
root.parent.mkdir(parents=True, exist_ok=True)
script = root.with_suffix('.json')
script.write_text(json.dumps({'version': 1, 'title': 'Moving window check', 'app': 'Showback Fixture', 'window': {'title': 'Showback Fixture'}, 'scenes': [
    {'say': "I'll move this window, then use its controls.", 'actions': [{'click': {'role': 'button', 'name': 'Move window'}}], 'expect': {'text': 'Window moved'}},
    {'say': "I'll sign in from the new position.", 'actions': [{'click': {'role': 'button', 'name': 'Sign in'}}], 'expect': {'text': 'Welcome, demo user'}},
    {'say': 'The welcome message appeared. This window remains the recording source while another test window covers it.', 'actions': [{'point': {'role': 'statictext', 'text': 'Welcome, demo user'}}], 'expect': {'text': 'Welcome, demo user'}}]}))

def call(*args):
    r = subprocess.run([desktop, '--session', 'showback-visual-check', *args], capture_output=True, text=True, timeout=15)
    value = json.loads(r.stdout)
    assert value.get('ok'), (args, value, r.stderr)
    return value['data']

process = subprocess.Popen([binary, 'run', str(script), '--mute', '--out', str(root)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
try:
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        assert process.poll() is None, process.communicate()
        if (root / 'run.json').exists():
            state = json.loads((root / 'run.json').read_text())
            if any(e['kind'] == 'scene' and e['scene'] == 3 for e in state.get('events', [])): break
        time.sleep(.05)
    else:
        raise AssertionError('Scene 3 never started')
    browser = next(w for w in call('list-windows', '--app', 'Showback Browser Fixture') if w['visible'])
    call('move-window', '--window-id', browser['id'], '--x=-1000', '--y', '50')
    call('focus-window', '--window-id', browser['id'])
    stdout, stderr = process.communicate(timeout=40)
    state = json.loads((root / 'run.json').read_text())
    assert process.returncode == 0 and state['status'] == 'completed', (stdout, stderr, state)
    points = [e for e in state['events'] if e['kind'] == 'point']
    # Sign-in pointer is in the newly moved window, not at its original desktop position.
    assert points[1]['data']['x'] > -950, points
    frame = Image.open(root / 'frames/scene-03.png').convert('RGB')
    assert frame.size == (760, 540), frame.size
    # Native fixture background is nearly uniform at the right; browser has distinct cards there.
    patch = frame.crop((600, 240, 700, 300))
    assert max(ImageStat.Stat(patch).stddev) < 3, 'An occluding window leaked into the capture'
    epoch = state['clockEpoch']
    transition = float(events.read_text()) - epoch
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(root/'recording.mp4'), '-vf', 'fps=30,crop=500:30:48:150,format=gray', '-f', 'rawvideo', '-'], capture_output=True, timeout=30)
    assert raw.returncode == 0, raw.stderr
    size = 500 * 30
    frames = [Image.frombytes('L', (500,30), raw.stdout[i:i+size]) for i in range(0,len(raw.stdout)-size+1,size)]
    baseline = frames[max(0,int(transition*30)-3)]
    changes = [(i/30, ImageStat.Stat(ImageChops.difference(f,baseline)).mean[0]) for i,f in enumerate(frames) if transition-.1 <= i/30 <= transition+.3]
    changed = next(t for t,diff in changes if diff > 1)
    lag = changed-transition
    assert abs(lag) <= .1, ('UI/video clock discrepancy exceeds 100ms', lag, changes)
    assert len(state['pointer']['marks']) == len(points) == 3, 'Each target has one pointer mark; no delayed completion effects'
    print(f'Moved pointer aligned; occlusion excluded; UI/video lag {lag*1000:.1f}ms.')
    print(root)
finally:
    if process.poll() is None:
        process.kill(); process.wait()
