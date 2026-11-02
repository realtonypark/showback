#!/usr/bin/env python3
"""Check offscreen navigation and finished-video delivery on a virtual display."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[1]
binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else repo / ".build/debug/showback").resolve())
display = os.environ["SHOWBACK_TEST_DISPLAY"]
assert os.environ.get("SHOWBACK_ASSETS"), "Set SHOWBACK_ASSETS to verified local assets."
fixture_binary = repo / ".local/gui/Showback Browser Fixture.app/Contents/MacOS/ShowbackBrowserFixture"

with tempfile.TemporaryDirectory(prefix="showback-walkthrough-") as temporary:
    root = Path(temporary)
    page = root / "page.html"
    page.write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><title>Walkthrough</title>
<style>body{font:24px system-ui;padding:40px;background:#eef3f0;color:#18352b}
button{font:inherit;padding:12px}section{margin-top:1200px}</style>
<h1>Walkthrough start</h1><button>Read more</button><button>Read more</button>
<section><h2>Details</h2><button onclick="this.textContent='Tour complete'">Continue tour</button></section>
</html>''')
    fixture = subprocess.Popen([str(fixture_binary), "--display", display, "--page", str(page)], cwd=root,
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    try:
        def run(name, scenes):
            assert fixture.poll() is None, fixture.communicate()
            script = root / (name + ".json")
            script.write_text(json.dumps({"version": 1, "title": name, "app": "Showback Browser Fixture",
                                          "window": {"title": "Showback Browser Fixture"}, "scenes": scenes}))
            bundle = root / (name + ".showback")
            process = subprocess.run([binary, "run", str(script), "--mute", "--out", str(bundle)],
                                     cwd=root, capture_output=True, text=True, timeout=60)
            result = json.loads((bundle / "run.json").read_text())
            return process, result, bundle

        ambiguous, state, _ = run("ambiguous", [{"actions": [{"point": {"role": "button", "name": "Read more"}}]}])
        assert ambiguous.returncode == 1 and state["status"] == "failed", ambiguous
        assert 'Scene 1, action 1' in state["error"] and 'name="Read more"' in state["error"] and 'found 2' in state["error"], state
        assert "Partial video: " + state["video"] in ambiguous.stdout, ambiguous.stdout

        process, state, bundle = run("tour", [
            {"say": "The walkthrough starts at the top.", "actions": [{"point": {"role": "heading", "name": "Walkthrough start"}}]},
            {"say": "I will reveal the next section and complete the tour.", "actions": [
                {"scroll-to": {"role": "button", "name": "Continue tour"}},
                {"click": {"role": "button", "name": "Continue tour"}}
            ], "expect": {"role": "button", "name": "Tour complete", "timeout": 5},
               "absent": {"role": "button", "name": "Continue tour", "timeout": 5}},
            {"say": "The tour is complete."}
        ])
        assert process.returncode == 0 and state["status"] == "completed" and state["mediaReady"], (process, state)
        video = Path(state["video"])
        assert video == bundle / "demo.mp4" and "Video: " + str(video) in process.stdout, process.stdout
        assert "Summary: " + str(bundle / "summary.md") in process.stdout, process.stdout
        assert not (bundle / ".incomplete").exists()
        assert len([e for e in state["events"] if e["kind"] in ("checked", "absent-checked")]) == 2, state
        streams = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_type", "-of", "json", str(video)],
                                 check=True, capture_output=True, text=True, timeout=10)
        assert {s["codec_type"] for s in json.loads(streams.stdout)["streams"]} == {"video", "audio"}, streams.stdout
        at = state["pointer"]["marks"][-1]["time"] + 0.4
        frame = subprocess.run(["ffmpeg", "-v", "error", "-ss", str(at), "-i", str(video), "-frames:v", "1",
                                "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], check=True, capture_output=True, timeout=10).stdout
        blue = sum(r < 90 and g > 100 and b > 180 for r, g, b in zip(frame[0::3], frame[1::3], frame[2::3]))
        assert blue > 100, ("Exported highlight is missing", blue)
        print("Ambiguity identifies the scene/action/selector; offscreen scroll-to succeeds; the advertised MP4 contains audio and highlights.")
    finally:
        fixture.terminate()
        try:
            fixture.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            fixture.kill()
            fixture.communicate()
