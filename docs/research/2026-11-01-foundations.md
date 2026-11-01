# Showback foundations

Initial research and accepted constraints from the design interview. Implementation has not started.

## User intent

- Let an agent demonstrate its output through actual computer use and speech.
- Use the agent-desktop skill and CLI as the desktop-control base.
- Support a short agent-authored demo script and a local runner.
- Show pointer movement, highlights, clicks, and narration.
- Support a live demo and a recorded bundle with a shareable MP4.
- Learn from Scrawl's implementation and structure.

## Verified local state

- `/Users/tpark/exp/showback` is an empty Git repository on `main`, without commits.
- The installed agent-desktop npm package reports version 1.0.2; its JSON protocol reports version 2.5.
- `agent-desktop status` reports macOS with Accessibility and Screen Recording granted. Automation permission is unknown.
- Swift, macOS `say`, and FFmpeg are installed. Their presence does not establish recording or speech quality.
- Scrawl's capture folder does not exist on this machine. Existing bundle inspection was not possible.

## agent-desktop

Sources: `/Users/tpark/.agents/skills/agent-desktop/SKILL.md`, installed CLI help, and version-matched `agent-desktop skills get platform` / `skills get desktop commands-system` / `skills get desktop commands-interaction`.

- Accessibility snapshots and searches expose actionable element refs.
- Refs belong to snapshots and can become stale after a UI change. Saved refs are unsuitable as persistent script targets. Resolve targets during each run.
- The CLI already provides a presentation cursor with animated travel, click ripples, element outlines, styling, and short labels.
- The presentation cursor does not move the OS pointer or activate the target app. Headless semantic actions also do not bring a window forward. A live presentation must account for visibility and focus explicitly.
- Headed actions permit physical input. Some actions remain semantic even in headed mode.
- Waits support UI conditions. They can replace fixed sleeps for application readiness; deliberate viewing time is a separate concern.
- Sessions provide traces and optional pre/post screenshots. Those artifacts are not a continuous video recording.
- Action results distinguish delivery from verified effect. Do not blindly retry actions that might already have landed.
- Overlay inclusion in a chosen capture mode, cursor timing, and audio synchronization still require runtime checks.

The [official repository](https://github.com/vercel-labs/agent-desktop) confirms the accessibility-based CLI and observe-act-observe workflow. Local version-matched docs are the authority for the installed behavior.

## Scrawl

Source root: `/Users/tpark/exp/scrawl`.

| Concern | Source | Lesson for Showback |
| --- | --- | --- |
| Native recording | `src/capture/macos.rs:1188`, `:1216` | ScreenCaptureKit with cursor inclusion and H.264 MP4 output. Reference the path without importing the whole app. |
| Export | `helper/Export.swift:6`, `:467` | Native media code consumes a plan, renders annotations, and combines audio and video. The existing plan includes much more than Showback may need. |
| Audio timing | `src/export/mod.rs:240`, `src/capture/macos.rs:1242` | Keep an explicit timeline and measured offsets. Recording start currently uses a midpoint estimate. |
| Live overlays | `src/laser_overlay.rs:120` | Click-through, nonactivating panels. Prefer agent-desktop's existing overlay before adding another renderer. |
| Coordinates | `src/screens.rs:1` | Distinguish desktop points, window-local points, and capture pixels. Retina scale and display origins matter. |
| Demo animation | `helper/OnboardingDemo.swift:15` | A deterministic animation of a pretend app, not a real desktop runner or TTS implementation. |
| Bundle | `src/model.rs:60`, `skills/scrawl/SKILL.md` | Keep source media, structured facts, and readable text separate. Do not make Showback inherit Scrawl's full schema. |

Scrawl is MIT licensed, copyright Kit Langton. Preserve its license notice if copying substantial code. Its native capture/export path uses Apple frameworks; this does not establish portability to Windows or Linux.

## Accepted constraints — November 1, 2026

- macOS first, including browser and native applications.
- Prepared scripts with runtime target lookup, waits for expected states, and stop on failure.
- Explicit invocation through a skill and CLI, rather than automatic demos after every agent completion.
- Three speech sources: Showback Cloud (provided free through OpenRouter free models), OpenRouter with the user's own key, and local speech models downloaded only with opt-in.
- Local speech is the default. The specific synthesis model and first-use download flow remain to be decided.
- English narration first.
- CLI and agent skill with a small native Settings window for voices, model downloads, and keys; no full desktop app for the first version.
- One curated local model with a few voices initially, rather than a model library.
- Record every demo by default, with a live-only option.
- Capture one app window by default. Demos spanning apps or windows require an explicit display choice.
- During implementation, commit in small, reviewable steps.
- Requested cloud candidates: `fish-audio/s2.1-pro-free:free` and `heygen/heygen-voice-1-turbo:free`.
- UI should use clear layout and direct controls; omit taglines, redundant helper text, and secondary labels.
- Make implementation trade-offs for UX, developer experience, and agent experience while preserving behavior. Use Ponytail full mode.

## Speech research — November 1, 2026

- The official [Fish Audio model page](https://openrouter.ai/fish-audio/s2.1-pro-free:free) describes a free variant intended for testing, prototyping, and low-volume applications, without production latency or availability guarantees.
- The official [HeyGen model page](https://openrouter.ai/heygen/heygen-voice-1-turbo:free) confirms retirement on November 30, 2026. Do not make this the sole basis of Showback Cloud.
- Neither exact ID appeared in the unauthenticated `https://openrouter.ai/api/v1/models` response during this check, despite both official model pages being present. Model-page presence alone does not verify API usability. Confirm the current speech-specific discovery and request contract before choosing a default.
- The screenshots are model-picker interaction references. For example, [Parakeet](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) is a speech-recognition model; it does not generate narration. Select actual speech-synthesis models for local output.
- A credential was supplied in chat. Its value is intentionally absent from all project files and tool calls. No authenticated requests were made. A distributed app must not contain the shared provider credential; Showback Cloud needs a server-side credential boundary. Rotate the supplied credential before deployment.

## Local synthesis candidates

Read-only source research identifies [Pocket TTS](https://github.com/kyutai-labs/pocket-tts) as the first runtime candidate for the English-first app: an MIT-licensed standalone Rust CPU runner, with macOS ARM and Intel binaries. Intel builds require AVX2/x86-64-v3. The model weights are CC BY 4.0 rather than MIT. The [non-cloning distribution](https://huggingface.co/kyutai/pocket-tts-without-voice-cloning) is ungated; the cloning distribution is gated. Published English weight files are approximately 219 MB (standard), 111.7 MB (18m), 66.5 MB (7m), and 46.7 MB (2m), excluding voice/tokenizer assets. Compare 18m with standard before selecting a shipping model.

[Voice provenance](https://huggingface.co/kyutai/tts-voices) must be checked separately from the model license: Alba is CC BY 4.0, some voices are CC0, and other presets carry noncommercial restrictions. Ship only eligible presets with required attribution.

[Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) is the alternate candidate: Apache 2.0 weights, approximately 327 MB original or [92.4 MB q8 ONNX](https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX), plus voices, runtime, and phonemizer. Its runtime integration has more parts than the standalone Pocket runner.

[Apple speech synthesis](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer) can provide a small system-voice baseline. Its [audio-buffer output](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/write(_:tobuffercallback:)) avoids recording narration through the microphone. Available voices vary by machine.

No candidate has been downloaded or executed. Compatibility, download size of the complete distribution, offline behavior, narration quality, and latency require validation before selecting a default model.

## Remaining decisions

Next decisions include cloud hosting and service limits, the local synthesis model, first-use download flow, narration pacing, user interruption, and speech-failure behavior. The script contract, failure reporting, bundle contents, and first acceptance demo also remain open. Verify provider APIs and local model compatibility before asking the user to choose between implementations.

## Checks still needed

No GUI actions, recording, speaker playback, speech-quality comparison, or runtime synchronization checks were performed. A narrated success claim is not evidence that the application reached the expected state; the design must distinguish the script's intent from observed results.
