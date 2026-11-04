# Contributing to Showback

Showback is a macOS-first, local-only demo runner. Start with a small bug fix, documentation correction, accessibility improvement, or example. Open an issue before starting a new platform, speech provider, or major feature.

## Build

Requires macOS 15+, Git, and Swift 6+ from Xcode command-line tools. No Swift package dependencies are needed.

```sh
git clone https://github.com/realtonypark/showback.git
cd showback
swift build -j 3
swift test -j 3
swift build -c release -j 3 -Xswiftc -warnings-as-errors
python3 scripts/check-signal-assertions.py
```

Python 3 is a QA dependency, not a product dependency. The basic suite needs no model download, provider key, or Accessibility/Screen Recording grants. CI runs these checks on macOS. GUI integration checks are separate.

To run the development executable against installed model assets:

```sh
./scripts/install.sh
export SHOWBACK_ASSETS="$HOME/Applications/Showback.app/Contents/Resources/Assets"
.build/debug/showback doctor
python3 scripts/check-cli.py
```

## Make a change

1. Fork the repository and create a branch from `main`.
2. Read the owning module's document below. Search for existing rules before adding another copy.
3. Keep the change focused. Add a regression for a behavior bug; documentation-only changes do not need new tests.
4. Run the relevant checks and submit a pull request explaining the user-visible result and any limitations.

| Concern | Start here |
| --- | --- |
| Script validation | `Sources/ShowbackCore/Script.swift`, [scripts](docs/scripts.md) |
| Desktop targets and session recovery | `Desktop.swift`, [desktop contracts](docs/desktop.md) |
| Speech, model assets, voice settings | `Speech.swift`, `Assets.swift`, `AudioPlayback.swift`, [speech](docs/speech.md) |
| Capture, pointers, video export | `Recording.swift`, `Presentation.swift`, `StopControl.swift`, `MediaExport.swift`, [recording](docs/recording.md) |
| Sequencing and durable results | `Runner.swift`, `RunBundle.swift`, [run results](docs/runs.md) |
| CLI surface | `CLI.swift` |
| App lifecycle | `Sources/Showback/Entry.swift`, `Application.swift` |
| Settings | `Settings.swift`, `SettingsStore.swift` |
| Shared infrastructure | `Paths.swift`, `Process.swift`, `Failure.swift`, `RunLock.swift` |
| Installation | `scripts/install.sh`, [installation](docs/installation.md) |

Use plain values between concerns. Keep rules in one owning module, validate untrusted input at boundaries, and prefer native frameworks over new dependencies. Do not introduce automatic action retries, guessed target coordinates, implicit whole-display capture, or cloud speech fallback.

## Test desktop and media changes

Use the controlled fixtures on a virtual display and follow [verification](docs/verification.md). Test audio stays muted; inspect generated files rather than playing through speakers. Never reset existing TCC grants, record unrelated desktop content, or send test actions to real accounts. An explicitly selected display can include everything visible on it.

The GUI tools may require ffmpeg, Pillow, NumPy, or SciPy as documented in the verification guide. Installer checks temporarily alter and restore entries in Showback's download cache; run them separately from installations.

For capture/export changes, inspect actual frames, audio, timing, and run status. For interruption changes, check partial media and session recovery. Do not call an unfinalized MP4 usable or describe a failed demo as successful.

## Submit a pull request

Include the problem, resulting behavior, and relevant verification. For visual changes, attach a short recording or screenshot using safe test data. Do not commit recordings, model weights, local logs, credentials, or personal data. Keep required third-party notices with copied or redistributed material.

Maintainers review pull requests as time permits; there is no response-time commitment. Be respectful, specific, and open to technical disagreement. Report vulnerabilities through [SECURITY.md](SECURITY.md), not a public issue.
