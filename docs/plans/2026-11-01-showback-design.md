# Showback design

Status: approved for implementation. Product choices below reflect the interview. Technical choices remain subject to the explicit validation gates below.

## Purpose

Showback lets an agent demonstrate actual software while narrating what it does. The agent authors a short demo script; a local runner presents it and saves a shareable video. A demo establishes only the outcomes that were actually checked. It does not replace the project's tests.

## Agreed product scope

- macOS first, for native applications and browser windows.
- Explicit invocation through a CLI and an agent skill.
- Prepared scripts with runtime target lookup and waits for expected states.
- Local, English narration using one curated model and a few eligible preset voices.
- Download the model together with Showback during installation. The first run does not need a separate model download.
- Live presentation and recording by default; a live-only option.
- One app window by default. Demos spanning apps or windows require an explicit display choice.
- Narration can overlap actions and cursor movement. Outcome statements follow successful checks.
- Stop through Ctrl+C or a small Stop control; preserve partial output and label cancellation. No pause/resume initially.
- A small native Settings window for voice selection and model status.
- No cloud TTS, BYOK, provider credentials, model catalog, full desktop application, or automatic demos after every agent completion.
- Clear controls and layout. No taglines or redundant helper text.

## User flow

1. Install Showback. The same operation installs the CLI, agent skill, required local runtimes, model, and preset voice assets. Show download progress and total size. A failed installation must leave a prior working installation usable and must not report success without the model.
2. The authoring agent inspects the actual app with agent-desktop, writes the script, and checks that the intended flow can run against the current app state. Script creation does not silently execute the demo.
3. Invoke `showback run demo.json`. The CLI validates the script, local assets, compatible desktop tooling, permissions, and capture target before any scripted interaction. If several windows match, report the candidates rather than picking one.
4. Prepare narration locally. Synthesis failure ends preparation before desktop actions begin. Do not substitute another voice or contact a provider automatically.
5. Start capture, bring the selected target into view, and run the scenes. Resolve each element from current state, show the pointer/highlight, perform the action, and check the expected result. Use UI-condition waits for readiness rather than fixed sleeps.
6. Finalize the MP4 and recording bundle. Print the absolute output path and the observed run status. A live-only run skips recording; checks and errors still apply.

`showback settings` opens the native voice settings. Settings does not contain keys, providers, or a model browser. The installer owns initial model installation; an absent or damaged model produces a repair instruction rather than a download during a presentation.

## Script contract

Use a small, versioned JSON format. A script identifies the app and window, capture scope, and an ordered list of scenes. Each scene can contain narration, ordered desktop actions, and an expected result. A scene's actions may run while its narration plays. The next scene starts only after narration, actions, and any expected-state wait have completed.

Illustrative shape; exact keys will be validated during implementation:

```json
{
  "version": 1,
  "title": "Sign-in flow",
  "app": "Example",
  "window": { "title": "Example" },
  "scenes": [
    {
      "say": "Let's open the account page.",
      "actions": [
        { "click": { "role": "button", "name": "Sign in" } }
      ],
      "expect": { "text": "Welcome" }
    },
    { "say": "The account page is now open." }
  ]
}
```

Selectors describe current UI targets rather than saved snapshot refs. Resolve exactly one target; ambiguity is an error. Start with the small set of actions needed for real demos: point, click, type, key press, scroll, and a bounded expected-state wait. Add no scripting language, branches, loops, arbitrary shell commands, or autonomous recovery. A visual coordinate target, if needed, must be explicitly tied to the selected window or display coordinate space; never fall back from a missing semantic target to guessed coordinates.

Narration text is authored content. The runner cannot establish whether every sentence is true. The authoring skill must place success claims after the relevant expected-state check. Saved output records which checks passed so viewers and agents can distinguish observed results from narration.

## Owning concerns

Use a small Swift executable hosted in an app bundle for native UI and media access. Swift's native frameworks cover settings, audio playback, capture, and media output without a web UI or new general-purpose runtime. Call the existing agent-desktop CLI for desktop observation and actions; do not copy its automation engine or depend on its private state files.

| Owner | Responsibility |
| --- | --- |
| Script | Decode and validate scripts; define scenes, selectors, actions, and expected results as plain values. |
| Runner | Sequence scenes, coordinate narration/actions, and produce observed run results. |
| Desktop | Use agent-desktop's public commands, session scope, live target lookup, delivery results, and presentation cursor. |
| Speech | Own the curated model/voice assets and local synthesis. |
| Recording | Capture the selected scope, align audio with video, and render MP4. |
| Bundle | Save source media, screenshots, event facts, and readable run results. |
| Settings | Display voice choices and model status; call the owning speech module. |
| CLI | Parse invocation, route commands, and report paths/errors. |

Keep each rule in its owner and add concise rules documentation as the concern is implemented. Use plain values between orchestration and native adapters. Do not introduce interfaces with one implementation or a cloud-provider abstraction.

## Local speech selection

Validate Pocket TTS's official standalone CPU runner and its non-cloning English models first. Compare the compact English model against standard English using short narration that includes UI labels, code identifiers, numbers, and punctuation. Verify the complete asset set, runtime compatibility, license/attribution, and offline synthesis before choosing the shipping model. Only preset voices eligible for distribution may ship.

Kokoro is the alternative if Pocket fails compatibility, quality, or packaging requirements. Native Apple speech is a development baseline, not an automatic replacement for the installed model. Do not make a model-selection UI while only one model is supported.

Pin release and asset identities, verify downloads, and ship required notices. Keep model assets outside the repository. Test supported architectures explicitly; do not promise all Intel Macs from the existence of an Intel download.

## Recording and synchronization

Use native ScreenCaptureKit and AVFoundation, taking Scrawl's explicit media-clock and rendering-plan approach without importing its app state or complete capture schema. Preserve license notices if substantial source is copied.

Generate narration before capture, then use actual playback and capture timing to place it on one monotonic timeline. Record scene/action/check times and capture-start offset. Keep source media and timing facts so an export failure does not discard the run.

The agent-desktop cursor is a separate presentation overlay. A selected-window recording may omit it. Before choosing the recording implementation, verify whether the selected window and the exact overlay can be captured together. If not, validate composition of cursor/highlight events into the selected-window video. Never silently record the whole display to solve this. Live and exported presentation must use the same action targets and timeline; measure discrepancies rather than assuming they match.

Initial audio scope is generated narration. Microphone input, system audio, music, camera, and voice cloning are outside this version. Produce H.264/AAC MP4 for sharing. No automatic upload or PR posting.

## Recording bundle

Proposed default location: `~/Movies/Showback/<run>.showback/`.

| File | Purpose |
| --- | --- |
| `demo.mp4` | Shareable recording, with narration and visible cursor/highlights. |
| `script.json` | The script that was run. |
| `run.json` | Target, timing, actions, observed checks, completion/failure/cancellation status, and errors. |
| `summary.md` | Short readable result with absolute paths and failed checks. |
| `frames/` | Screenshots of meaningful scene results. |
| Source video and narration audio | Recovery and export inputs. |

Keep an incomplete or failed export explicitly marked. An unfinalized video must not be reported as a usable MP4. Do not overwrite an existing bundle or delete source media as part of failure handling. No retention service or custom archive format initially.

## Failure and interruption

- Validate unsupported scripts, missing assets, permission failures, and ambiguous capture targets before interaction where possible.
- Stop on missing/ambiguous UI targets, expected-state timeout, speech failure, or capture failure. Keep the failure reason and last observed state.
- Respect agent-desktop's delivery/retry disposition. An action may already have landed even if its verification timed out. Do not repeat it blindly.
- Ctrl+C and Stop cease new actions and narration, close recording safely, and mark the bundle cancelled. Preserve completed observations; do not describe cancellation as success.
- Do not roll back app state or restart a partial script automatically. The authoring agent must inspect the current state before proposing another run.
- Scope each run to its own desktop session and avoid competing Showback runs controlling the same machine.

## Verification and implementation order

1. Validate local synthesis offline and the window-plus-overlay recording path. These are the technical viability gates; report any required product change before making it.
2. Implement script validation and a small real-app walkthrough with target lookup, waits, and checked results. Include focused checks for invalid input, ambiguous targets, and failure/cancellation sequencing.
3. Coordinate narration, visible interaction, recording, and bundle finalization. Use native buffer/file audio rather than microphone loopback.
4. Add the installer, installed skill, and small native Settings window. Exercise installation, reinstall, and interrupted-download behavior without damaging a working install.
5. Validate a controlled browser demo and a native-app demo. Inspect video frames, audio, screenshots, and structured results. Check cursor/highlight inclusion, measured synchronization, truncated audio, static-screen recording, target movement, expected-state failure, and cancellation. Use an agreed synchronization tolerance and record measured results before claiming it passes.
6. Re-run the installed command offline after asset installation, without provider credentials. Verify failed runs cannot produce successful result status.

Commit in small, reviewable steps on local `main`. Check each step before committing and keep the working tree clean. Use a controlled test app and safe test data. Do not play test audio through speakers or record unrelated desktop content during validation. Preserve the human's current app state where the test does not explicitly need to change it.

## Outstanding implementation evidence

The model, runtime, architecture support, minimum OS, capture/filter strategy, complete install size, setup time, and synchronization tolerance still need measurements. These are verification work, not established behavior. The user approved implementation and iterative build/test/fix verification.
