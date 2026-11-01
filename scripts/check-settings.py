#!/usr/bin/env python3
"""Exercise native Settings recovery/selection without playing a voice preview."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else ".build/debug/showback").resolve())
assets = Path(os.environ["SHOWBACK_ASSETS"])
desktop = str(assets / "bin/agent-desktop")
settings = Path.home() / "Library/Application Support/Showback/settings.json"
original = settings.read_bytes() if settings.exists() else None
settings.parent.mkdir(parents=True, exist_ok=True)
settings.write_text('{"voice":"removed-voice"}')
process = subprocess.Popen([binary, "settings"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
scope = "showback-settings-check-" + str(process.pid)

def call(*args):
    result = subprocess.run([desktop, "--session", scope, *args], capture_output=True, text=True, timeout=15)
    value = json.loads(result.stdout)
    assert value.get("ok"), (args, value, result.stderr)
    return value["data"]

try:
    deadline = time.monotonic() + 10
    window = None
    while time.monotonic() < deadline:
        assert process.poll() is None, ("Settings exited instead of allowing voice repair", process.communicate())
        result = subprocess.run([desktop, "--session", scope, "list-windows", "--app", "showback"], capture_output=True, text=True, timeout=10)
        value = json.loads(result.stdout)
        windows = value.get("data", [])
        window = next((item for item in windows if item.get("pid") == process.pid and item.get("title") == "Showback Settings"), None)
        if window:
            break
        time.sleep(0.05)
    assert window, "Settings window did not appear"
    base = ["--app", window["app_name"], "--window-id", window["id"]]
    sheet = call("find", *base, "--surface", "sheet", "--role", "button", "--name", "OK", "--exact")
    assert len(sheet["matches"]) == 1, sheet
    call("click", sheet["matches"][0]["ref_id"])
    popup = call("find", *base, "--role", "combobox", "--name", "Voice", "--exact")
    assert len(popup["matches"]) == 1, popup
    call("select", popup["matches"][0]["ref_id"], "Marius")
    assert json.loads(settings.read_text())["voice"] == "marius"
    current = call("find", *base, "--role", "combobox", "--name", "Voice", "--exact")
    assert current["matches"][0]["value"] == "Marius", current
    snapshot = Path(".local/settings-verified.png").resolve()
    snapshot.parent.mkdir(exist_ok=True)
    call("screenshot", str(snapshot), *base)
    close = call("find", *base, "--role", "button", "--name", "Close", "--exact")
    call("click", close["matches"][0]["ref_id"])
    process.communicate(timeout=10)
    assert process.returncode == 0
    print("Native Settings recovered an invalid voice, persisted selection, and closed cleanly.")
finally:
    if process.poll() is None:
        process.terminate()
        try:
            process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill(); process.communicate()
    if original is None:
        if settings.exists(): settings.unlink()
    else:
        settings.write_bytes(original)
