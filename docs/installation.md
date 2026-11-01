# Installation

`scripts/install.sh` owns app/CLI/skill activation. `Sources/ShowbackCore/Assets.swift` owns verified downloads and the installed asset receipt. `Sources/ShowbackCore/Resources/assets.json` is the source of asset versions, sizes, hashes, paths, and voices. `Sources/ShowbackCore/Resources/version.txt` owns the app version; `Package.swift` owns the minimum macOS version.

- Stage the complete installation before replacing a working app. Install the model and runtimes in the same operation as the CLI and skill.
- Verify cached and downloaded bytes, including each extracted archive member, against pinned SHA-256 identities. The mutable receipt does not authorize file hashes. Never treat a partial/corrupt download as installed.
- Sign the app locally without changing the pinned runtime binaries. Verify the installed command before discarding backups.
- Restore the previous app, CLI, and skill if activation or installed verification fails.
- The installed app must use its installed resource bundle, never a fallback into the build checkout.
- No provider keys, microphone permission, account, cloud relay, or runtime model download is needed.

Use `python3 scripts/check-install.py` to exercise installation/reinstallation and a corrupt-cache plus blocked-download update. That check uses an isolated prefix and restores the temporarily altered Showback cache file.
