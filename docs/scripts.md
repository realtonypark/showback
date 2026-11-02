# Scripts

`Sources/ShowbackCore/Script.swift` owns version-1 script parsing and validation. It returns plain scene, action, selector, and condition values. Rendering does not interpret script rules.

- Reject unknown fields, unknown actions, booleans used as numbers, empty targets, and invalid timeouts.
- Limit scripts to 1 MiB, 100 scenes, and 100 actions per scene. Narration is at most 5,000 characters per scene; typed text is at most 10,000.
- Conditions use selector fields plus a timeout: default 15 seconds, greater than zero and no more than 300 seconds. A scene `expect` passes when a direct match exists; a scene `absent` passes when no direct match exists. Use both to prove an error is gone and the intended state is present.
- Persist selectors rather than snapshot refs. An action has exactly one command. Control actions map to agent-desktop semantic verbs: `point`, `click`, `type`, `set-value`, `clear`, `focus`, `select`, `check`, `uncheck`, `toggle`, `expand`, `collapse`, `scroll`, `scroll-to`, `press`, and `wait`. The agent chooses the app and content to present; the script only drives and checks that surface.
- Scene app/window overrides require explicit display capture. A scene without overrides targets the root app/window.
- Do not add shell execution, loops, autonomous repair, or guessed coordinate fallback.

Run `swift test -j 3 --filter ScriptTests` and `showback validate SCRIPT.json` after schema changes. Update callers, skill examples, and README in the same change.

`validate` checks the schema only. Prepare live targets and verify uncertain navigation before a narrated run, then restore the starting state. Accessibility text presence does not establish that a section is visible. Use an explicit `scroll-to` or a tested scroll route before pointing or clicking offscreen content.
