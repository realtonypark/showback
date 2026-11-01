# Showback

Showback lets an agent demonstrate real software with local narration, visible interaction, checked outcomes, and a shareable MP4.

## Install

Requires macOS 15 or later and Xcode command-line tools with Swift 6. Installation downloads about 134 MB of pinned model, voice, and runtime assets. Python and Node are not required to run Showback.

```sh
./scripts/install.sh
~/.local/bin/showback doctor
```

The installer creates:

- `~/Applications/Showback.app`, including the local model and runtimes.
- `~/.local/bin/showback`.
- `~/.agents/skills/showback/`, for coding agents that discover shared skills.

Add `~/.local/bin` to your shell's `PATH` if necessary. Start a new agent session to discover the installed skill. The installer takes an optional absolute prefix for an isolated installation: `./scripts/install.sh /tmp/showback-test`.

Model download is part of installation. Runs do not download models or use an inference provider. A failed update restores the previous app, CLI, and skill. Source installation signs the app locally; Developer ID signing and notarized public releases are not included.

Before the first demo, grant Accessibility and Screen Recording to the app that launches Showback when required. `showback doctor` prints their current status. The guided permission panel is available through `showback desktop permissions --guide`. Showback does not need microphone access.

## Use

Ask your coding agent to use Showback to demonstrate a change. It can load the installed skill, inspect the actual app, write a script, and run it. Demos are requested explicitly; they do not run after every code change.

```sh
showback validate demo.json
showback run demo.json
showback run demo.json --mute
showback run demo.json --live-only
showback settings
```

`--mute` keeps narration in the recording without speaker playback. `--live-only` skips video capture. Ctrl+C or the Stop control cancels the demo and preserves its partial output. Pause/resume is not included.

Settings provides voice selection and local model status. The curated English model is Pocket TTS 18M with Alba, Marius, and Javert voices. There is no cloud TTS or BYOK mode.

## Scripts

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

Each scene waits for its narration, actions, and expected state to finish. Narration may overlap actions. Put success claims in a later scene, after checking the result. The runner checks UI predicates; it cannot determine whether arbitrary narration is true.

Targets use accessibility `role`, `name`, `text`, or `nativeID`. They are resolved when used; scripts do not store transient desktop refs. Ambiguous action targets fail. Supported actions are point, click, type, select, press, scroll, and wait; see the [authoring skill](skills/showback/SKILL.md) for shapes and constraints.

Window capture is the default. Use `showback desktop list-displays` and an explicit `"capture": {"display": DISPLAY_ID}` for a demo spanning windows/apps. A scene can then override `app` and `window`; each scene defaults back to the root app/window. Display capture records everything on that display. Showback never widens capture automatically.

`showback desktop <args>` exposes the bundled agent-desktop CLI. Start with `showback desktop skills get desktop` and `showback desktop skills get platform` for its version-matched contracts.

## Output

Recordings default to `~/Movies/Showback/<run>.showback/`. Set a destination with `--out /absolute/path/demo.showback`.

| File | Contents |
| --- | --- |
| `demo.mp4` | H.264 video with AAC narration and rendered pointer/highlights. |
| `script.json` | The script that ran. |
| `run.json` | Actual scene, action, check, pointer, and narration times; final status and errors. |
| `summary.md` | Readable status, observed checks, and absolute output paths. |
| `frames/` | Meaningful scene results, with presentation effects. |
| `recording.mp4`, `narration/` | Source video and prepared narration for diagnosis/recovery. |

A failed or cancelled run retains that status even if its partial MP4 exports successfully. `.incomplete` means recording/export did not finish. Existing bundles are not overwritten. Files remain local; uploading a video or posting to a PR is a separate action.

## Development

```sh
swift test -j 3
swift build -j 3
SHOWBACK_ASSETS=/absolute/assets/path python3 scripts/check-cli.py
python3 scripts/check-install.py
```

`SHOWBACK_ASSETS` selects an existing verified asset directory for development. The installed app uses its own bundled assets by default. GUI checks use controlled fixtures on a virtual display; see [verification](docs/verification.md).

Verified runtime behavior and outstanding platform coverage are listed in that document. Apple Silicon is the tested architecture; the Intel runtime requires AVX2 and still needs hardware validation.

## Implementation

- [Scripts](docs/scripts.md)
- [Desktop contracts](docs/desktop.md)
- [Speech and settings](docs/speech.md)
- [Recording](docs/recording.md)
- [Run results](docs/runs.md)
- [Installation](docs/installation.md)

Scrawl informed the capture, timing, and bundle design. The [third-party notices](Sources/ShowbackCore/Resources/THIRD-PARTY.md) describe the runtime, model, and voice licenses.
