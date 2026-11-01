#!/usr/bin/env python3
"""Install/reinstall in a temporary prefix; verify a failed download preserves it."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
installer = repo / "scripts/install.sh"
assert installer.exists(), "Showback installer is missing"

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

with tempfile.TemporaryDirectory(prefix="showback-install-") as temporary:
    prefix = Path(temporary)
    def install(command=None):
        return subprocess.run((command or []) + [str(installer), str(prefix)], cwd=repo, capture_output=True, text=True, timeout=180)

    catalog = json.loads((repo / "Sources/ShowbackCore/Resources/assets.json").read_text())
    tokenizer = next(asset for asset in catalog["downloads"] if asset["id"] == "tokenizer")
    token_cache = Path.home() / "Library/Caches/Showback/Downloads" / tokenizer["sha256"]
    token_backup = token_cache.with_name(token_cache.name + ".download-test-backup")
    assert token_cache.exists() and not token_backup.exists()
    token_cache.rename(token_backup)
    try:
        first = install()
        assert first.returncode == 0, (first.stdout, first.stderr)
        assert token_cache.exists() and digest(token_cache) == tokenizer["sha256"], "Fresh download was not verified/cached"
    finally:
        if token_cache.exists(): token_cache.unlink()
        token_backup.rename(token_cache)
    app = prefix / "Applications/Showback.app"
    binary = app / "Contents/MacOS/showback"
    entry = prefix / ".local/bin/showback"
    skill = prefix / ".agents/skills/showback/SKILL.md"
    assert binary.exists() and skill.exists()
    assert (app / "Contents/Resources/Assets/installed.json").exists()
    doctor = subprocess.run([str(entry), "doctor"], capture_output=True, text=True, timeout=15)
    assert doctor.returncode == 0 and "Pocket TTS" in doctor.stdout, doctor
    second = install()
    assert second.returncode == 0, (second.stdout, second.stderr)
    before = [digest(path) for path in [binary, entry, skill]]

    catalog = json.loads((repo / "Sources/ShowbackCore/Resources/assets.json").read_text())
    voice = next(asset for asset in catalog["downloads"] if asset["id"] == "voice-javert")
    cache = Path.home() / "Library/Caches/Showback/Downloads" / voice["sha256"]
    backup = cache.with_name(cache.name + ".install-test-backup")
    assert cache.exists() and not backup.exists()
    cache.rename(backup)
    try:
        cache.write_bytes(b"interrupted download")
        policy = '(version 1)(allow default)(deny network-outbound (remote ip "*:*"))'
        failed = install(["/usr/bin/sandbox-exec", "-p", policy, "/bin/bash"])
        assert failed.returncode != 0, "A corrupt asset plus blocked download unexpectedly succeeded"
    finally:
        if cache.exists():
            cache.unlink()
        backup.rename(cache)
    assert before == [digest(path) for path in [binary, entry, skill]], "Failed installation changed the working app/CLI/skill"
    doctor = subprocess.run([str(entry), "doctor"], capture_output=True, text=True, timeout=15)
    assert doctor.returncode == 0, doctor
    assert not list((prefix / "Applications").glob(".showback-install.*")), "Installation stage leaked"
print("Install, reinstall, corrupt-download rejection, and prior-install preservation passed.")
