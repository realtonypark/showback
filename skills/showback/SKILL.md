---
name: showback
description: Demonstrate actual software with local narration, visible interaction, checked outcomes, and a shareable MP4 when the user requests a Showback walkthrough or recorded demo.
---

# Showback

Use Showback when a demonstration is requested. Do not run it automatically after ordinary coding work. It operates real applications and changes their state.

Check `showback doctor`, then read the installed desktop contracts:

```sh
showback desktop skills get desktop
showback desktop skills get platform
```

`showback desktop` forwards to the bundled agent-desktop CLI. Use its observe/act/verify loop to inspect the intended app and establish the starting state. Preserve existing authorization boundaries; a demo request does not authorize purchases, publishing, deleting user data, or changing account settings. Use safe test data for such flows.

Write a short version-1 JSON script. `app` is the exact application display name. Use `window.title` to select an exact window title when the app has more than one window. Find targets at runtime by accessible `role`, `name`, `text`, or `nativeID`; saved snapshot refs are not script targets.

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

Narration may overlap a scene's actions. The next scene waits for its audio, actions, and expected state to finish. Put outcome claims in a scene after the corresponding check. Explain what the viewer can observe; a checked demo does not establish that every bug is fixed or replace the project's tests. Write speech as spoken English, expanding code identifiers where pronunciation would be unclear.

Actions:

- `{"point": SELECTOR}` highlights a target without acting on it.
- `{"click": SELECTOR}` clicks through accessibility.
- `{"type": {"target": SELECTOR, "text": "Demo note"}}` inserts text using the target's desktop contract.
- `{"select": {"target": SELECTOR, "option": "Marius"}}` selects a named native or web option.
- `{"press": "cmd+a"}` sends a key combination to the selected window.
- `{"scroll": {"target": SELECTOR, "direction": "down", "amount": 3}}` scrolls a target.
- `{"wait": {"text": "Saved", "timeout": 10}}` waits for a UI condition. A scene-level `expect` has the same condition format.

Use one action key per action. Selectors combine `role`, `name`, `text`, and `nativeID`. Conditions use those fields plus a timeout in seconds (default 15, maximum 300). Action targets must resolve uniquely; `expect` passes when a direct match exists, `absent` passes when no direct match exists. To prove a fix, check both: `expect` the intended state and set `absent` to the old error, for example `"absent": {"text": "404"}`. Window selection waits up to 15 seconds for a single window to appear; ambiguous windows still stop the run. Scripts have no shell commands, loops, guessed coordinate fallback, or autonomous recovery.

Window capture is the default. For a demo that deliberately spans windows or apps, obtain the display ID from `showback desktop list-displays` and add `"capture": {"display": 4}` using the actual chosen ID. Display capture includes everything on that display. Do not broaden capture silently. A scene may then override `app` and `window` to select another app/window on that display. Each scene defaults to the root app/window; repeat overrides for a follow-up outcome scene in the other app. Scene switching is rejected in window capture mode.

```sh
showback validate demo.json
showback run demo.json
showback run demo.json --mute --out /absolute/path/demo.showback
showback run demo.json --live-only
```

Installation includes the local model. A run must not download models or contact an inference provider. `--mute` saves narration in the video without speaker playback. Ctrl+C or the Stop control cancels the run and preserves partial output.

After a run, read `summary.md` and `run.json`, inspect the saved scene images, and inspect the recording when practical. Report the absolute MP4/bundle path, observed checks, and any failed or cancelled status. Do not describe an incomplete export as a usable video. If a run fails, inspect the app's current state before authoring another run; actions may already have landed. Sharing a local file is separate from uploading it or posting to a PR.
