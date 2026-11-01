#!/usr/bin/env python3
"""Check signal-helper session assertions without a GUI or real desktop sessions."""
import contextlib
import io
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
from types import SimpleNamespace
from unittest.mock import patch

script = Path(__file__).with_name('check-signals.py')

class ForcedProcess:
    def __init__(self, arguments, **kwargs):
        self.pid = 123
        self.returncode = None
        root = Path(arguments[arguments.index('--out') + 1])
        root.mkdir()
        (root / 'run.json').write_text(json.dumps({'status': 'running', 'events': [{'kind': 'narration-start'}]}))
        (root / '.incomplete').touch()
    def poll(self): return self.returncode
    def send_signal(self, value): pass
    def communicate(self, **kwargs):
        self.returncode = 130
        return '', ''
    def kill(self): self.returncode = -9
    def wait(self): return self.returncode


def check(stale, change_history=False):
    before = [{'session_id': 'history', 'ended_at': 1}]
    if stale:
        before.append({'session_id': 'prior-forced', 'ended_at': None})
    forced = [{'session_id': 'history', 'ended_at': 1}, {'session_id': 'new-forced', 'ended_at': None}]
    if stale:
        forced.append({'session_id': 'prior-forced', 'ended_at': 2})
    after = [dict(entry, ended_at=3) if entry['session_id'] == 'new-forced' else dict(entry) for entry in forced]
    if change_history:
        after[0]['ended_at'] = 99
    snapshots = [before, forced, after]
    def command(arguments, **kwargs):
        if arguments[1:3] == ['desktop', 'session']:
            return SimpleNamespace(returncode=0, stdout=json.dumps({'data': {'sessions': snapshots.pop(0)}}), stderr='')
        assert arguments[1] == 'run' and '--live-only' in arguments, arguments
        return SimpleNamespace(returncode=1, stdout='', stderr='Expected missing app')
    output = io.StringIO()
    with patch.dict(os.environ, {'SHOWBACK_ASSETS': '/unused-test-assets'}), patch.object(sys, 'argv', [str(script)]), \
         patch.object(subprocess, 'Popen', ForcedProcess), patch.object(subprocess, 'run', command), \
         patch.object(os, 'waitpid', return_value=(123, 0)), contextlib.redirect_stdout(output):
        runpy.run_path(str(script), run_name='__main__')
    assert not snapshots
    return output.getvalue()

check(False)
assert 'Recovered 1 pre-existing unfinished session' in check(True)
try:
    check(True, change_history=True)
except AssertionError as error:
    assert 'previously ended' in str(error).lower(), error
else:
    raise AssertionError('The helper accepted a changed historical session')
print('Signal helper accepts expected stale recovery and still rejects changed historical records.')
