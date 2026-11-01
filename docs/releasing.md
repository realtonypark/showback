# Maintainer release checklist

The current launch is a source-first developer preview. This checklist does not publish a release automatically.

1. Review the final changes on `main`. Confirm CI passes and [platform coverage](verification.md) matches the release claims.
2. Keep `Sources/ShowbackCore/Resources/version.txt` as the version source. Update it when preparing a new version, along with user-facing release notes.
3. Run the Swift suite and strict release build from [CONTRIBUTING.md](../CONTRIBUTING.md). Exercise source install/reinstall and failed-update recovery before installer releases.
4. For desktop/media changes, inspect controlled native and browser runs, narration, source/final media, failure/cancellation status, and session recovery. Keep test playback muted and use a virtual display.
5. Recheck download identities and attribution when changing a runtime, model, tokenizer, or voice. Pin both archives and extracted members. Do not commit downloaded weights or recordings.
6. Update the README, quickstart, example scripts, and safe demo media together when the workflow changes. Verify relative links and commands from the repository root.
7. Prepare release notes with installation instructions, supported/verified environments, changes, and known limits. Create a tag and GitHub release only when the maintainer is ready to publish them.

A source release must state that installation needs Swift 6+ and that its app is ad hoc signed. Do not advertise a Homebrew formula, signed download, notarization, Intel validation, or macOS 15 hardware validation until that work is complete.

A future binary release additionally needs Developer ID signing/notarization, artifact checksums, required notices, clean-machine Gatekeeper/TCC checks, and verified architecture/OS coverage. Keep signing credentials out of the repository and fork PR workflows.
