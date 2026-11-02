# Getting started

## Install from source

Requires macOS 15+, Git, and Xcode command-line tools with Swift 6+. Check `swift --version`; if the command is missing, install Apple's command-line tools with `xcode-select --install`. If the installed Swift is older than 6, update your Xcode/toolchain before building.

```sh
git clone https://github.com/realtonypark/showback.git
cd showback
./scripts/install.sh
export PATH="$HOME/.local/bin:$PATH"
showback doctor
```

The installer builds locally and downloads approximately 134 MB of pinned assets, including the English model and three voices. Installation commonly takes a few minutes. The installed app occupies roughly 143 MiB. The first run has no separate model download. Developer tools and network access are needed for installation; runs work offline afterward.

For an isolated prefix, use `./scripts/install.sh /absolute/prefix`. The app, CLI, and skill are then placed under that prefix's `Applications`, `.local/bin`, and `.agents/skills` directories.

## Permissions

```sh
showback desktop permissions --guide
showback doctor
```

Follow the guide to grant Accessibility and Screen Recording to the app that launches Showback, such as Terminal or your coding-agent host. Showback does not require microphone access. Permission grants belong to the launching context; a terminal check does not establish that a different agent host has the same grants. Do not reset existing grants as a troubleshooting shortcut.

## First recording

Open `~/Applications/Showback.app`. Its Settings window shows the local model and voice picker. Once it is visible, run from the checkout:

```sh
showback validate examples/showback-demo.json
showback run examples/showback-demo.json --mute
```

This example only points at Settings; it does not change the selected voice. `--mute` keeps generated narration in the MP4 but silences live playback. Omit it for a spoken presentation.

The command prints the final status and absolute bundle path. Open `demo.mp4` inside a completed bundle. Read `summary.md` and `run.json` for observed checks and errors; `.incomplete` indicates unfinished media. A partial video does not turn a failed or cancelled run into success.

## Agent setup

The installer copies [the authoring skill](../skills/showback/SKILL.md) to `~/.agents/skills/showback/`. Restart the agent session to refresh discovery. If your host reads another skill directory, copy that folder to the host's configured location:

```sh
mkdir -p /path/to/your/agent/skills
cp -R skills/showback /path/to/your/agent/skills/
```

Hosts differ; this shared-directory install is not a promise that every host auto-discovers it.

Ask the agent to inspect the actual running app, author a short script using current labels, and run a checked walkthrough. Do not reuse snapshot refs as script selectors. Success statements belong after the scene that checks the result.

## Common problems

| Symptom | Next step |
| --- | --- |
| `showback: command not found` | Run `~/.local/bin/showback --version`; add `~/.local/bin` to PATH. |
| Missing or damaged model/runtime | Re-run `./scripts/install.sh` from an updated checkout. Demos do not download repairs while presenting. |
| Permission denied | Run the permission guide from the same terminal/agent host that will run the demo. |
| Window not accessible | Unlock macOS, wait for the app to finish opening, and inspect `showback desktop list-windows`. |
| More than one matching window | Set the exact `window.title` in the script. |
| Target missing or ambiguous | Inspect fresh accessibility state and narrow the selector. Do not guess coordinates or blindly repeat an action. |
| Settings parse/voice error | Open `showback settings` and select an available voice. |
| Previous demo was force-stopped | The next run recovers its recorded session before creating another; retain incomplete media for diagnosis. |
| Intel speech runtime fails | AVX2 is required. Intel hardware remains unverified; include architecture and tool output in a bug report. |

## Update and remove

From a clean checkout, run `git pull --ff-only` and `./scripts/install.sh`. The installer stages and verifies the new app, CLI, and skill before activation and restores the previous installation on failure.

To remove Showback, delete the installed app, `~/.local/bin/showback`, and `~/.agents/skills/showback`. Recordings in `~/Movies/Showback`, preferences in `~/Library/Application Support/Showback`, and caches in `~/Library/Caches/Showback` remain until you choose to remove them. Review recordings before sharing or deleting them.
