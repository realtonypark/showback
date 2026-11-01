#!/usr/bin/env python3
"""Check real CLI startup and failure status without changing an application."""
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile

binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else ".build/debug/showback").resolve())
with tempfile.TemporaryDirectory(prefix="showback-cli-") as temporary:
    root = Path(temporary)
    script = root / "demo.json"
    script.write_text(json.dumps({"version": 1, "title": "Missing app", "app": "Showback Nonexistent Verification App", "scenes": [{"say": "This must not play."}]}))
    version = subprocess.run([binary, "--version"], capture_output=True, text=True, timeout=10)
    assert version.returncode == 0 and re.fullmatch(r"Showback \d+\.\d+\.\d+\n", version.stdout), version
    validated = subprocess.run([binary, "validate", str(script)], capture_output=True, text=True, timeout=10)
    assert validated.returncode == 0 and "Valid:" in validated.stdout, validated
    invalid = subprocess.run([binary, "run", str(script), "--slient"], capture_output=True, text=True, timeout=10)
    assert invalid.returncode != 0 and "Unknown run option" in invalid.stderr, invalid
    if os.environ.get("SHOWBACK_ASSETS"):
        output = root / "failed.showback"
        failed = subprocess.run([binary, "run", str(script), "--mute", "--out", str(output)], capture_output=True, text=True, timeout=15)
        assert failed.returncode != 0, failed
        result = json.loads((output / "run.json").read_text())
        assert result["status"] == "failed" and not result["mediaReady"], result
        assert not (output / "demo.mp4").exists()
print("CLI startup, validation, and failure checks passed.")
