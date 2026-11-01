# Showback Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Install and run local, narrated desktop demos with checked outcomes and shareable recorded bundles.

**Architecture:** A Swift executable/app bundle owns scripts, orchestration, speech, media, and Settings in separate files. It calls agent-desktop's public CLI and an installed local synthesis runtime; each run has an isolated session and bundle.

**Tech Stack:** Swift Package Manager, Foundation, AppKit, AVFoundation, ScreenCaptureKit, agent-desktop, curated local TTS.

**Spec:** `docs/plans/2026-11-01-showback-design.md`

## Global Constraints

- Local `main`; small verified commits; no cloud TTS or provider credentials.
- Installation includes the model, runtime, CLI, and agent skill.
- English first, one model, a few eligible preset voices.
- Record by default, one app window by default, display only by explicit choice.
- Runtime target lookup, condition waits, checked results; fail rather than guess or retry a possibly delivered action.
- No speaker playback or unrelated desktop recording during tests.

## Review Focus

- Interrupted installation must preserve the old working installation.
- Unknown script fields and ambiguous/missing targets must fail before unsafe actions.
- Cancellation and failed checks must never become successful result status.
- A selected-window recording must include presentation effects without unrelated overlapping windows.
- Offline synthesis and export must include complete narration on the correct video timeline.

### Task 1: Establish speech and recording viability

**Files:** `docs/verification.md`, ignored `.local/` experiments.
**Interfaces:** Select an offline TTS invocation and capture/composition strategy that later modules implement.

- [x] Download pinned official runtime/model assets and verify identities and licenses.
- [x] Generate file audio offline; inspect duration, sample rate, samples, and synthesis time without speaker playback. Compare compact and standard models.
- [x] On a controlled virtual display, test window capture and presentation effects, including unrelated occluding windows. Document whether capture or composition is required.
- [x] Commit measured evidence and any technical ruling.

### Task 2: Scripts and desktop execution

**Files:** `Package.swift`, `Sources/ShowbackCore/{Script,Desktop,Process,Paths}.swift`, `Sources/Showback/main.swift`, `Tests/ShowbackCoreTests/ScriptTests.swift`, `examples/`.
**Interfaces:** `DemoScript.load(URL) throws -> DemoScript`; `Desktop` owns window selection, session lifecycle, target lookup, actions, and expected-state waits. Subprocesses take argument arrays, never shell strings.

- [x] Write checks for valid scripts, unknown fields/actions, invalid bounds/timeouts, and missing/ambiguous targets. Watch them fail.
- [x] Implement strict script decoding, validation command, scoped desktop sessions, and public CLI adaptation.
- [x] Run the full Swift tests and controlled app walkthrough. Commit.

### Task 3: Narrated runs and recoverable bundles

**Files:** `Sources/ShowbackCore/{Speech,Runner,RunBundle,SettingsStore}.swift`, `Sources/Showback/{Presentation,Recording,Settings,Application}.swift`, focused tests and verification fixtures.
**Interfaces:** `Speech.prepare` produces local audio clips; `Runner` sequences scenes and writes run facts; `Recording` accepts the selected target and action timeline and returns finalized media paths. Settings calls the speech owner.

- [x] Write failing tests for asset errors, result status, bundle no-overwrite, and cancellation/failure sequencing.
- [x] Implement pre-synthesis, narration/action overlap, checked scene boundaries, Stop/Ctrl+C, live-only mode, and partial-output preservation.
- [x] Implement the viable window capture/effect composition path and H.264/AAC output. Keep original video/audio and record actual timing.
- [x] Inspect real output frames/audio/manifest and failed/cancelled runs. Run full tests and commit working increments.

### Task 4: Installation, Settings, and authoring skill

**Files:** `scripts/install.sh`, pinned asset manifest, `skills/showback/SKILL.md`, `README.md`, subsystem rules docs, installer checks.
**Interfaces:** Installation creates a stable app bundle, CLI entry point, skill, and verified offline asset directory. `showback doctor` reports prerequisites; `showback settings` opens native voice controls.

- [x] Write installer failure/reinstall checks before implementation; simulate interrupted and corrupted downloads without altering the existing app.
- [x] Implement staged verified installation, architecture checks, license notices, voice selection, and direct repair errors.
- [x] Test the installed CLI, skill files, Settings UI, reinstall, and offline synthesis. Commit.

### Task 5: End-to-end audit

**Files:** controlled native/browser fixtures, verification scripts, `docs/verification.md`.
**Interfaces:** Installed `showback run` is the authority; fixtures never send data to real services.

- [x] Validate native and browser demos, moving targets, static screens, ambiguity, missing targets, failed expectations, synthesis errors, cancellation, and offline operation.
- [x] Inspect MP4 streams, frame samples, screenshots, narration, and run facts; measure synchronization to a 100 ms target and report actual results.
- [x] Run full checks and a fresh whole-branch review. Fix material findings with regression checks; commit fixes.
- [x] Audit every design requirement against current evidence before claiming completion.

The requirement audit and measured evidence are in `docs/verification.md`. Platform limits remain explicit there.
