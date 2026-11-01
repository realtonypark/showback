#!/usr/bin/env python3
"""A failed metadata write must not skip capture/session cleanup (GUI fixture required)."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else '.build/debug/showback').resolve())
desktop = str(Path(os.environ['SHOWBACK_ASSETS']) / 'bin/agent-desktop')
def sessions():
    value = subprocess.run([desktop, 'session', 'list'], capture_output=True, text=True, timeout=10)
    assert value.returncode == 0, value.stderr
    return {s['session_id']: s for s in json.loads(value.stdout)['data']['sessions']}
before = sessions()
with tempfile.TemporaryDirectory(prefix='showback-persistence-') as temporary:
    root = Path(temporary)
    script = root / 'demo.json'
    script.write_text(json.dumps({'version': 1, 'title': 'Persistence failure', 'app': 'Showback Fixture',
                                 'scenes': [{'say': 'This narration runs while the test checks that a failed metadata save still closes the recording and desktop session safely.'}]}))
    bundle = root / 'failed.showback'
    process = subprocess.Popen([binary, 'run', str(script), '--mute', '--out', str(bundle)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            assert process.poll() is None, process.communicate()
            metadata = bundle / 'run.json'
            if metadata.exists() and any(e['kind'] == 'narration-start' for e in json.loads(metadata.read_text()).get('events', [])):
                break
            time.sleep(.05)
        else:
            raise AssertionError('Narration never started')
        metadata.unlink()
        metadata.mkdir()
        process.send_signal(signal.SIGINT)
        stdout, stderr = process.communicate(timeout=30)
        assert process.returncode != 0, (stdout, stderr)
        after = sessions()
        created = [value for key, value in after.items() if key not in before]
        assert len(created) == 1 and created[0].get('ended_at'), ('Desktop session not closed', created)
        probe = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'json', str(bundle / 'recording.mp4')], capture_output=True, text=True, timeout=10)
        assert probe.returncode == 0 and float(json.loads(probe.stdout)['format']['duration']) > 0, (probe.stdout, probe.stderr)
        assert (bundle / '.incomplete').exists(), 'Failed metadata persistence must keep incomplete marker'
        print('Metadata write failure still finalized source video and closed the desktop session.')
    finally:
        if process.poll() is None:
            process.kill(); process.wait()
