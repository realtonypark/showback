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
def sessions():
    result = subprocess.run([binary, 'desktop', 'session', 'list'], capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, result.stderr
    return {entry['session_id']: entry for entry in json.loads(result.stdout)['data']['sessions']}
before = sessions()
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
        forced = sessions()
        created = [key for key in forced if key not in before]
        assert len(created) == 1 and not forced[created[0]].get('ended_at'), forced
        recovery_script = Path(temporary) / 'recovery.json'
        recovery_script.write_text(json.dumps({'version': 1, 'title': 'Recovery check',
            'app': 'Showback Nonexistent Recovery Verification App', 'scenes': [{'say': 'This must not be spoken.'}]}))
        recovered = subprocess.run([binary, 'run', str(recovery_script), '--mute', '--live-only', '--out', str(Path(temporary) / 'recovery.showback')],
                                   capture_output=True, text=True, timeout=20)
        assert recovered.returncode == 1, (recovered.stdout, recovered.stderr)
        after = sessions()
        assert after[created[0]].get('ended_at'), 'The forced-exit desktop session was not recovered'
        assert all(entry.get('ended_at') for key, entry in after.items() if key not in before), after
        assert all(after[key].get('ended_at') == value.get('ended_at') for key, value in before.items()), 'An unrelated session was changed'
        print('Second signal forced exit; the next run recovered its session and left unrelated sessions untouched.')
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
