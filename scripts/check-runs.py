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
    stop_helper = root / "click-stop"
    subprocess.run(["swiftc", "Tests/Fixtures/ClickStop.swift", "-o", str(stop_helper)], check=True, capture_output=True, timeout=30)
    def script(name, scenes):
        path = root / (name + ".json")
        path.write_text(json.dumps({"version": 1, "title": name, "app": "Showback Fixture", "window": {"title": "Showback Fixture"}, "scenes": scenes}))
        return path

    blocked = script("speech-failure", [{"say": "This cannot be synthesized.", "actions": [{"click": {"role": "button", "name": "Increment"}}]}])
    blocked_bundle = root / "speech-failure.showback"
    runtime = str(Path(os.environ["SHOWBACK_ASSETS"]) / "bin/pocket-tts")
    policy = '(version 1)(allow default)(deny process-exec (literal ' + json.dumps(runtime) + '))'
    synthesis = subprocess.run(["/usr/bin/sandbox-exec", "-p", policy, binary, "run", str(blocked), "--mute", "--out", str(blocked_bundle)], capture_output=True, text=True, timeout=25)
    state = json.loads((blocked_bundle / "run.json").read_text())
    assert synthesis.returncode == 1 and state["status"] == "failed", synthesis
    assert not state["events"] and not (blocked_bundle / "recording.mp4").exists(), state
    assert "Preparing narration" in synthesis.stdout, (synthesis.stdout, synthesis.stderr)
    print("Synthesis failure stopped preparation before capture or actions.", flush=True)

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

    stopped_bundle = root / "stop-control.showback"
    process = subprocess.Popen([binary, "run", str(long_script), "--mute", "--out", str(stopped_bundle)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            assert process.poll() is None, process.communicate()
            try:
                state = json.loads((stopped_bundle / "run.json").read_text())
                if any(event["kind"] == "scene" for event in state.get("events", [])): break
            except FileNotFoundError:
                pass
            time.sleep(0.05)
        else:
            raise AssertionError("Run never started")
        clicked = subprocess.run([str(stop_helper), str(process.pid)], capture_output=True, text=True, timeout=15)
        assert clicked.returncode == 0, (clicked.stdout, clicked.stderr)
        stdout, stderr = process.communicate(timeout=30)
        state = json.loads((stopped_bundle / "run.json").read_text())
        assert process.returncode == 130 and state["status"] == "cancelled" and state["mediaReady"], (stdout, stderr, state)
        print("Native Stop button cancelled playback and retained a partial MP4.", flush=True)
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

    # This closes only the isolated test fixture's window; restart it before another suite run.
    closing = script("capture-loss", [{
        "say": "This narration should stop as soon as the recording source disappears. It must not keep talking after the demonstration window is closed.",
        "actions": [{"click": {"role": "button", "name": "Close"}}]
    }, {"say": "This later scene must never run."}])
    closed_bundle = root / "capture-loss.showback"
    lost = subprocess.Popen([binary, "run", str(closing), "--mute", "--out", str(closed_bundle)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        deadline = time.monotonic() + 25
        while time.monotonic() < deadline:
            state = json.loads((closed_bundle / "run.json").read_text()) if (closed_bundle / "run.json").exists() else {}
            if state.get("clockEpoch") is not None: break
            assert lost.poll() is None, lost.communicate()
            time.sleep(.05)
        else:
            raise AssertionError("Capture-loss presentation never started")
        started = time.monotonic()
        stdout, stderr = lost.communicate(timeout=15)
        elapsed = time.monotonic() - started
    finally:
        if lost.poll() is None:
            lost.kill(); lost.wait()
    state = json.loads((closed_bundle / "run.json").read_text())
    assert lost.returncode == 1 and state["status"] == "failed", (stdout, stderr, state)
    assert elapsed < 5, ("Capture loss did not stop narration promptly", elapsed, stdout, stderr)
    assert [event["scene"] for event in state["events"] if event["kind"] == "scene"] == [1], state
    print("Capture loss stopped narration and prevented subsequent scenes.")
