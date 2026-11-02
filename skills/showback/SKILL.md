---
name: showback
description: Demonstrate actual software with local narration, visible interaction, checked outcomes, and a shareable MP4 when the user requests a Showback walkthrough or recorded demo.
---

# Showback

Use Showback for a requested demonstration. It operates real applications and changes their state. A walkthrough means audible live narration plus a recorded video unless the user requests another mode. Keep existing authorization boundaries: use safe test data; purchases, publishing, deletion, and account changes need their own authorization.

## 1. Prepare the surface

Batch these independent reads in one tool turn, then read their complete results:

```sh
showback doctor
showback desktop skills get desktop
showback desktop skills get platform
```

Desktop contracts arrive in JSON `data.content`; decode that field when needed instead of truncating the envelope. `showback desktop` forwards to the bundled agent-desktop CLI. Look up an unfamiliar command's `--help` once, rather than guessing flags.

Use an isolated desktop session for preparation. Common commands (replace the IDs and app/labels with observed values; keep the same session on every preparation command):

```sh
showback desktop session start --name Showback-preparation
showback desktop --session SESSION_ID list-windows --app "Example"
showback desktop --session SESSION_ID focus-window --window-id WINDOW_ID
showback desktop --session SESSION_ID snapshot --app "Example" --window-id WINDOW_ID --include-bounds
showback desktop --session SESSION_ID find --app "Example" --window-id WINDOW_ID --role button --name "Sign in" --exact --limit 0
```

Inspect the intended app/window, open the requested page, and verify its actual content. A running browser or an HTTP 200 does not establish that its selected tab shows the requested page. For address-bar navigation, focus the field before typing or setting its value and pressing Enter. Wait for UI readiness after navigation; a transient accessibility error is not a missing page.

Choose a short route through the requested result. Resolve each distinct action target with a fresh, window-scoped `find`. Use exact role/name pairs, including punctuation, or a native ID. Require one direct match, not the first result. If those fields cannot distinguish duplicates, choose another unique target/route or report the targeting limit. `--text` searches can include ancestors and offscreen content; combine text with a role. Saved snapshot refs are for preparation actions only, never script targets.

Rehearse uncertain navigation/scroll transitions, not every demo action. Keep state-changing actions for the recorded run unless an authorized reset route is already known; finding a button does not require clicking it during preparation. Bring each section into view and inspect its position, not just whether its text exists in the accessibility tree. Prefer `scroll-to` when the target supports it; otherwise test focused page scrolling (`focus` the scroll area, then `press` Page Down/Home) or another app-supported route. A scrollbar value can be rounded by the app, and an error may still mean it moved. Follow the desktop delivery contract and inspect state before choosing another action.

Restore and verify the starting page, scroll position, focus, and any test state after preparation. Close only your preparation session with `showback desktop session end SESSION_ID`. Completion criterion: the start is visible, action targets are unique, and uncertain transitions have an observed working route.

## 2. Author the script

Write a version-1 JSON script using the exact app display name and `window.title` from inspection. Keep generated scripts and media outside the app repository to avoid unrelated build/lint hooks. Use absolute paths; run from a scratch directory if the agent's hooks scan its working directory. Default bundles go to `~/Movies/Showback/`.

```json
{
  "version": 1,
  "title": "Account flow",
  "app": "Example",
  "window": { "title": "Example" },
  "scenes": [
    {
      "say": "I'll open the account page.",
      "actions": [{ "click": { "role": "button", "name": "Sign in" } }],
      "expect": { "text": "Welcome", "timeout": 10 }
    },
    { "say": "The welcome message appeared." }
  ]
}
```

Narration overlaps a scene's actions. The next scene waits for its audio, actions, and checks. Use one visual idea per scene so the pointer stays with the explanation. Put outcome claims after the scene that checks them. Write spoken English and expand code identifiers when pronunciation would be unclear. A walkthrough establishes observed states, not that every bug is fixed.

Use one action key per action. Selectors combine `role`, `name` (exact), `text` (substring), and `nativeID`. Action targets must be unique. Conditions use selector fields plus `timeout` in seconds (default 15, maximum 300). `expect` needs a direct match; `absent` needs no direct match. These checks establish accessibility presence, not visibility: explicitly reveal a section before pointing at it. For a fix, check the intended state with `expect` and the old error with `absent`.

Actions:

- `{"point": SELECTOR}` highlights visible content without changing it.
- `{"click": SELECTOR}` clicks through accessibility.
- `{"type": {"target": SELECTOR, "text": "Demo note"}}` inserts text using the target's desktop contract.
- `{"set-value": {"target": SELECTOR, "text": "Demo note"}}` sets a field directly.
- `{"select": {"target": SELECTOR, "option": "Marius"}}` selects a named option.
- `{"press": "cmd+a"}` sends a key combination to the selected window; focus its intended recipient first.
- `{"scroll": {"target": SELECTOR, "direction": "down", "amount": 3}}` scrolls a target.
- `{"scroll-to": SELECTOR}` reveals a target, then highlights its fresh position. Use it before clicking an offscreen link.
- `{"wait": {"text": "Saved", "timeout": 10}}` waits for a condition; scene-level `expect` uses the same format.
- `{"clear": SELECTOR}`, `{"focus": SELECTOR}`, `{"check": SELECTOR}`, `{"uncheck": SELECTOR}`, `{"toggle": SELECTOR}`, `{"expand": SELECTOR}`, and `{"collapse": SELECTOR}` use the matching desktop control.

Window capture is the default. For a deliberately multi-window/app demo, obtain a display ID with `showback desktop list-displays` and set `"capture": {"display": ID}`. Display capture includes everything on that display; do not broaden capture to recover from offscreen page content. Only display-scoped scripts may override `app`/`window` per scene. Each scene otherwise defaults to the root app/window; repeat overrides for follow-up scenes in another app.

## 3. Present

```sh
showback validate /absolute/path/demo.json
showback run /absolute/path/demo.json
```

Validation checks the schema, not live targets or navigation. Preserve the run's exit status and read progress/errors; a pipeline ending in `tail` can mask failure and hide the useful output. Installation includes the local model; runs must not download models or contact an inference provider.

Use plain `run` for the requested spoken walkthrough. `--mute` silences live speakers but keeps narration in the exported video; use it only for requested quiet output or automated tests. `--live-only` omits video. `--out /absolute/path/demo.showback` chooses a new bundle. Ctrl+C or Stop cancels and preserves partial output.

If a run fails, read its summary and the named scene/action in `script.json`. Inspect the app's current state: earlier actions may have landed. Repair the observed cause, restore the start, and run to a fresh output bundle. Preserve earlier bundles instead of deleting evidence. Do not retry uncertain actions automatically or replay a full demo just to locate its video. Scripts have no shell commands, loops, guessed coordinates, or autonomous repair.

## 4. Verify and deliver

Read the printed `Summary:` path and `run.json`. A successful recorded delivery requires `status: completed`, `mediaReady: true`, and a finalized video. The CLI's `Video:` line and `run.json.video` identify the absolute exported path; older bundles name it in `summary.md`. Check the gates with the absolute bundle path:

```sh
bundle=/absolute/path/to/demo.showback
test -f "$bundle/demo.mp4"
test "$(plutil -extract status raw -o - "$bundle/run.json")" = completed
test "$(plutil -extract mediaReady raw -o - "$bundle/run.json")" = true
```

**Deliver `demo.mp4`.** It contains narration and pointer/highlight overlays. `recording.mp4` is raw source video without them. Do not select a file by size or by the word "recording" in its name. Failed/cancelled runs may have a `Partial video:`; label that status even if it plays. `.incomplete` means media did not finalize.

Inspect saved scene images and a representative frame from **the exported video**, especially after a navigation or highlight change. When media inspection tools are available, check the exported audio track if narration was authored. State which checks actually ran; a `completed` status alone does not establish the audio track or overlay in a different file.

Report the absolute finished video path and observed checks. If asked to reveal it in Finder, use `open -R "/absolute/bundle/demo.mp4"`. The file is already local; no download or rerun is needed. Uploading or posting it elsewhere is a separate action.
