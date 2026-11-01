#!/usr/bin/env python3
"""Verify a second stop signal forces exit; requires the isolated native fixture."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else '.build/debug/showback').resolve())
assert os.environ.get('SHOWBACK_ASSETS'), 'Set SHOWBACK_ASSETS to verified local assets.'
with tempfile.TemporaryDirectory(prefix='showback-force-stop-') as temporary:
    root = Path(temporary) / 'run.showback'
    script = root.with_suffix('.json')
    script.write_text(json.dumps({'version': 1, 'title': 'Force stop check', 'app': 'Showback Fixture', 'scenes': [
        {'say': 'This presentation is running while we verify that a second stop signal can interrupt cleanup and end the process immediately.'}
    ]}))
    process = subprocess.Popen([binary, 'run', str(script), '--mute', '--out', str(root)],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        deadline = time.monotonic() + 25
        while time.monotonic() < deadline:
            assert process.poll() is None, process.communicate()
            if (root / 'run.json').exists():
                state = json.loads((root / 'run.json').read_text())
                if any(event['kind'] == 'narration-start' for event in state.get('events', [])):
                    break
            time.sleep(.05)
        else:
            raise AssertionError('Run never started')
        # Queue two distinct signals while stopped so both reach the event handlers before cleanup.
        process.send_signal(signal.SIGSTOP)
        os.waitpid(process.pid, os.WUNTRACED)
        process.send_signal(signal.SIGINT)
        process.send_signal(signal.SIGTERM)
        process.send_signal(signal.SIGCONT)
        stdout, stderr = process.communicate(timeout=5)
        state = json.loads((root / 'run.json').read_text())
        assert process.returncode == 130 and state['status'] == 'running' and (root / '.incomplete').exists(), (process.returncode, stdout, stderr, state)
        print('Second stop signal forced exit; incomplete marker and partial source preserved.')
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
