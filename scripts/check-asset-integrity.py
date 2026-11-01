#!/usr/bin/env python3
"""An edited runtime plus forged mutable receipt must not pass installed verification."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else '.build/debug/showback').resolve())
source = Path(os.environ['SHOWBACK_ASSETS']).resolve()
with tempfile.TemporaryDirectory(prefix='showback-integrity-') as temporary:
    assets = Path(temporary) / 'Assets'
    shutil.copytree(source, assets)
    environment = dict(os.environ, SHOWBACK_ASSETS=str(assets))
    def doctor():
        return subprocess.run([binary, 'doctor'], env=environment, capture_output=True, text=True, timeout=20)
    baseline = doctor()
    assert baseline.returncode == 0, (baseline.stdout, baseline.stderr)
    runtime = assets / 'bin/pocket-tts'
    data = bytearray(runtime.read_bytes())
    data[-1] ^= 1
    runtime.write_bytes(data)
    receipt_path = assets / 'installed.json'
    receipt = json.loads(receipt_path.read_text())
    receipt.setdefault('files', {})['bin/pocket-tts'] = {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    receipt_path.write_text(json.dumps(receipt))
    corrupted = doctor()
    assert corrupted.returncode != 0 and 'Integrity check failed for pocket-tts' in corrupted.stderr, ('Tampered runtime and receipt were trusted', corrupted.stdout, corrupted.stderr)
print('Forged receipt cannot bless a modified runtime.')
