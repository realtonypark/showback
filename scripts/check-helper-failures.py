#!/usr/bin/env python3
"""Check helper failure paths without opening a GUI or changing real preferences."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='showback-helper-check-') as temporary:
    root = Path(temporary)
    environment = dict(os.environ, HOME=str(root), SHOWBACK_ASSETS=str(root / 'assets'), PYTHONPATH=os.pathsep.join(sys.path))
    settings = root / 'Library/Application Support/Showback/settings.json'
    for original in [b'{"voice":"javert"}', None]:
        if original is not None:
            settings.parent.mkdir(parents=True, exist_ok=True)
            settings.write_bytes(original)
        elif settings.exists():
            settings.unlink()
        failed = subprocess.run([sys.executable, str(repo / 'scripts/check-settings.py'), str(root / 'missing-showback')],
                                cwd=repo, env=environment, capture_output=True, text=True, timeout=10)
        assert failed.returncode != 0 and 'FileNotFoundError' in failed.stderr, failed
        assert (settings.read_bytes() if settings.exists() else None) == original, 'Settings changed after failed launch'
    environment['SHOWBACK_FIXTURE_EVENTS'] = str(root / 'events.txt')
    output = root / 'new/nested/visual.showback'
    failed = subprocess.run([sys.executable, str(repo / 'scripts/check-visual.py'), str(root / 'missing-showback'), str(output)],
                            cwd=repo, env=environment, capture_output=True, text=True, timeout=10)
    assert failed.returncode != 0 and 'FileNotFoundError' in failed.stderr, failed
    assert json.loads(output.with_suffix('.json').read_text())['title'] == 'Moving window check'
print('Failed Settings launches preserve original/absent preferences; fresh visual output parents are created.')
