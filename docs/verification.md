# Verification

Core implementation checks are complete. This is an evidence log, not a claim that all supported hardware has been tested.

## Environment
- Apple Silicon MacBook Pro, macOS 26.2, Swift 6.3.3.
- GUI tests use a temporary 1,280 × 800 virtual display under `/tmp/pro-gui.lock`.
- Native and WebKit browser fixtures use safe local data. Test narration is muted; generated/exported audio is inspected from files, including on-device transcription.

## Established evidence
- Release compilation passes with `-warnings-as-errors`; both timer callbacks assert main-actor isolation on the main run loop.
- 29 Swift checks pass, covering script boundaries, desktop ambiguity, process timeout/environment/binary output, asset integrity, audio validation, pixel scale, reduced-motion pointer placement, rendered pointer export, result status, and run exclusion.
- `scripts/check-cli.py`: real entry-point startup, script validation, bad flags, and a missing-app failed result.
- `scripts/check-runs.py`, also run against the final installed app: denied speech-runtime execution stops preparation before capture/actions; failed expectations prevent later narration; cancellation preserves a cancelled MP4; concurrent demos are refused; live-only does not capture; asset/output paths containing spaces, `#`, and `:` work.
- `scripts/check-install.py`: source install, reinstall, corrupt-cache rejection with blocked network, and preservation of the prior app/CLI/skill all passed. A fresh URLSession tokenizer download also passed checksum verification.
- The default installer completed at `~/Applications/Showback.app`, `~/.local/bin/showback`, and `~/.agents/skills/showback`. Its installed doctor found the model and reported Accessibility and Screen Recording granted.
- `scripts/check-settings.py`, also run against the installed app and installed assets: the native Settings window recovered an invalid saved voice, selected Marius through the accessibility contract, persisted that selection, and closed cleanly. No voice preview was played.
- Capture loss now stops narration promptly and prevents later scenes. The regression first reproduced a falsely completed run after its window closed, then passed with source visibility monitoring and capture-error cancellation.
- A native fixture walkthrough produced a completed 760 × 540 H.264/AAC MP4 with three checked scene screenshots. Pointer placement and image density were inspected visually after fixing a scale error.
- A local WebKit browser walkthrough produced a completed 900 × 620 H.264/AAC MP4. Its checked welcome state and cursor were inspected visually.
- An explicit display-scoped two-app walkthrough produced a completed 1,280 × 800 H.264/AAC MP4. App switching worked; the source excluded Showback's controls and used one rendered cursor.
- The compact model generated 7.08 seconds of test speech in 0.83 seconds total; standard English generated 6.68 seconds in 1.82 seconds. This is a single local measurement, not a benchmark claim.
- On-device transcription recovered the complete native exported narration through its final sentence. The compact model's first short synthesis check preserved the intended UI instructions; the standard model did not improve that check.
- The installed self-demo `~/Movies/Showback/showback-demo-final.showback` completed with outbound IP networking denied. Its three expected-state checks passed. The H.264/AAC export contains the complete narration, independently transcribed from the MP4; all narration used muted audio-device playback.
- Marius and Javert each synthesized the account/welcome/check sentence locally; on-device transcription recovered the complete sentence for both voices.
- The native Stop button was pressed through the public Accessibility API. The run stopped with cancelled status and retained a playable partial MP4. agent-desktop's window inventory omits status-bar-level panels, so the control check uses `Tests/Fixtures/ClickStop.swift`.
- A fresh whole-project review found one cleanup defect. A regression first proved that a failed metadata write left its desktop session open; after the fix, the same failure finalized the source video and ended the session. All 29 Swift checks remained green.
- Waveform correlation against all five source clips in the installed self-demo measured exported narration placement within 0.05 ms of the recorded timeline (correlation 0.9918–0.9946). This checks encoded audio placement; the separate fixture measurement below checks UI/video timing.
- The moved-window walkthrough `.local/visual-v4.showback` completed with fresh controls resolved after movement. An overlapping WebKit window stayed out of the window-only video and final screenshot. Visual inspection confirmed the target outline and pointer remained aligned. Comparing the fixture's monotonic sign-in event against decoded source-video frames measured 21.7 ms of UI/video lag, within the 100 ms target.
- The first timing check found a completion-timed click ripple 145 ms late. It was removed: the desktop CLI does not expose the exact input-delivery time. Pointer travel/outlines remain shared between live and exported output; run action events report completion.

- The final installed cancellation/failure harness passed after the timer-isolation change, including speech preparation failure, native Stop, Ctrl+C, failed checks, competing runs, live-only, special paths, and capture loss. Its capture-loss deadline starts when presentation begins, excluding model preparation.

## Platform coverage

The build targets macOS 15+. Intel runtime assets require AVX2; Intel and macOS 15 hardware behavior remain unverified. Test fixtures are not evidence that a specific user's application or project tests pass.


## Reproduce controlled GUI checks

Build the fixtures with `./scripts/build-fixtures.sh`. The virtual-display helper is development-only and adapted from Scrawl under its MIT license. It uses a private macOS API; it is not part of Showback.

```sh
mkdir /tmp/pro-gui.lock # stop if another task owns it
.local/gui/virtual-display --width 1280 --height 800 --scale 1 --place left --seconds 3600
```

Keep that process running. Use its printed display ID below, never the physical display. The session must be unlocked. `SHOWBACK_TEST_DISPLAY` selects the virtual display for `check-settings.py`. In a separate terminal:

```sh
open -n '.local/gui/Showback Fixture.app' --args --display DISPLAY_ID --events /absolute/showback/.local/ui-transition.txt
open -n '.local/gui/Showback Browser Fixture.app' --args --display DISPLAY_ID --page /absolute/showback/Tests/Fixtures/browser.html
export SHOWBACK_ASSETS=/absolute/showback/.local/assets
python3 scripts/check-runs.py
```

`check-runs.py` closes the native fixture window at its end. Quit that fixture process and relaunch it before running `check-persistence.py` or `check-visual.py`. Both apps use local test data. The fixtures refuse a missing or primary display. `check-visual.py` also needs Pillow/ffmpeg and `SHOWBACK_FIXTURE_EVENTS` set to the `--events` path; use a fresh output bundle each time. `check-audio-sync.py /absolute/run.showback` needs NumPy, SciPy, and ffmpeg. These are QA tools, not product dependencies.

Stop the virtual-display process and remove only the lock you created when finished. No test changes real TCC grants or plays narration through speakers.

## Requirement audit

| Requirement | Evidence |
| --- | --- |
| CLI, skill, local model installed together | Default install plus isolated fresh-download/reinstall/failed-update checks; installed doctor and skill validator. |
| Local English speech, curated presets, no cloud | Outbound-IP-denied installed demo; all three voices file-transcribed; no provider credential path. |
| Native/browser demonstrations with current selectors | Completed native, WebKit, and Showback Settings demos; missing/ambiguous target checks. |
| Stop on failed checks, capture loss, or cancellation | Real-run harness verifies later narration is prevented and cancelled/failed status remains explicit. |
| Window scope by default; explicit display for multi-app | Isolated window/occlusion check and explicit two-app display walkthrough. |
| Shared pointer/highlight and synchronized export | Moved-window screenshot inspection, 21.7 ms UI/video measurement, and all-scene narration waveform correlation. |
| Default H.264/AAC recording; live-only alternative | Inspected MP4 streams; live-only harness confirms no source/final video. |
| Recoverable bundle without overwrites | Bundle tests, cancelled partial MP4, source preservation, and metadata-failure cleanup regression. |
| Native voice Settings | Installed UI recovers invalid voice and persists a new selection; test restores original preferences. |
| Small local product | Swift native frameworks, no package dependencies, no Node/Python product runtime, no upload/PR automation. |

The final installed self-demo contains 26.18 seconds of H.264 video and complete AAC narration. All three expected-state checks passed; five clips used the audio-device clock at zero playback volume. On-device transcription recovered every sentence through the final line.

Installed app size measured 146,072 KiB (~143 MiB), including assets. Download size is approximately 134 MB. Setup time on a clean machine was not benchmarked.
