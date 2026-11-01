#!/usr/bin/env python3
"""Exercise real cancellation and failures against the isolated native fixture."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else ".build/debug/showback").resolve())
assert os.environ.get("SHOWBACK_ASSETS"), "Set SHOWBACK_ASSETS to verified local assets."

with tempfile.TemporaryDirectory(prefix="showback-runs-") as temporary:
    root = Path(temporary)
    def script(name, scenes):
        path = root / (name + ".json")
        path.write_text(json.dumps({"version": 1, "title": name, "app": "Showback Fixture", "window": {"title": "Showback Fixture"}, "scenes": scenes}))
        return path

    failed_script = script("failed", [
        {"say": "Checking the expected state.", "expect": {"role": "statictext", "text": "This state must never exist", "timeout": 0.2}},
        {"say": "This later claim must not be spoken."}
    ])
    failed_bundle = root / "failed.showback"
    failed = subprocess.run([binary, "run", str(failed_script), "--mute", "--out", str(failed_bundle)], capture_output=True, text=True, timeout=30)
    assert failed.returncode == 1, failed
    result = json.loads((failed_bundle / "run.json").read_text())
    assert result["status"] == "failed" and result["mediaReady"], result
    assert [event["scene"] for event in result["events"] if event["kind"] == "scene"] == [1], result
    assert not any(event["kind"] == "checked" for event in result["events"]), result
    assert len(result["narration"]) == 1 and (failed_bundle / "demo.mp4").exists()
    print("Failed expectation preserved media and prevented later narration.", flush=True)

    long_script = script("cancelled", [{"say": "This presentation is running while we verify that stopping it prevents every later action and every later success claim."}, {"say": "This must not be reached."}])
    cancelled_bundle = root / "cancelled.showback"
    process = subprocess.Popen([binary, "run", str(long_script), "--mute", "--out", str(cancelled_bundle)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise AssertionError(process.communicate())
            try:
                state = json.loads((cancelled_bundle / "run.json").read_text())
                if any(event["kind"] == "scene" for event in state.get("events", [])):
                    break
            except FileNotFoundError:
                pass
            time.sleep(0.05)
        else:
            raise AssertionError("Run never started")
        concurrent = subprocess.run([binary, "run", str(long_script), "--mute", "--out", str(root / "concurrent.showback")], capture_output=True, text=True, timeout=10)
        assert concurrent.returncode == 1 and "Another Showback run" in concurrent.stderr, concurrent
        assert not (root / "concurrent.showback").exists()
        process.send_signal(signal.SIGINT)
        stdout, stderr = process.communicate(timeout=30)
        assert process.returncode == 130, (process.returncode, stdout, stderr)
        state = json.loads((cancelled_bundle / "run.json").read_text())
        assert state["status"] == "cancelled" and state["mediaReady"], state
        assert [event["scene"] for event in state["events"] if event["kind"] == "scene"] == [1]
        assert (cancelled_bundle / "recording.mp4").exists() and (cancelled_bundle / "demo.mp4").exists()
        print("Cancellation preserved a partial MP4; concurrent control was refused.", flush=True)
    finally:
        if process.poll() is None:
            process.kill(); process.wait()

    live_script = script("live", [{"say": "This live-only check has no video recording."}])
    live_bundle = root / "live.showback"
    live = subprocess.run([binary, "run", str(live_script), "--mute", "--live-only", "--out", str(live_bundle)], capture_output=True, text=True, timeout=20)
    assert live.returncode == 0, live
    state = json.loads((live_bundle / "run.json").read_text())
    assert state["status"] == "completed" and not state["recording"] and not state["mediaReady"]
    assert not (live_bundle / "recording.mp4").exists() and not (live_bundle / "demo.mp4").exists()
    print("Live-only mode completed without capturing video.")

    alias = root / "Assets # local: speech"
    alias.symlink_to(Path(os.environ["SHOWBACK_ASSETS"]).resolve(), target_is_directory=True)
    environment = dict(os.environ, SHOWBACK_ASSETS=str(alias))
    special = subprocess.run([binary, "run", str(live_script), "--mute", "--live-only", "--out", str(root / "Output # run: demo.showback")],
                             env=environment, capture_output=True, text=True, timeout=20)
    assert special.returncode == 0, special
    print("Model and output paths with spaces, #, and colon worked.")
