# Verification

Implementation verification is in progress. This is an evidence log, not a claim that all supported hardware has been tested.

## Environment

- Apple Silicon MacBook Pro, macOS 26.2, Swift 6.3.3.
- GUI tests use a temporary 1,280 × 800 virtual display under `/tmp/pro-gui.lock`.
- Native and WebKit browser fixtures use safe local data. Test narration is muted; generated/exported audio is inspected from files, including on-device transcription.

## Established evidence

- 28 Swift checks pass, covering script boundaries, desktop ambiguity, process timeout/environment/binary output, asset integrity, audio validation, pixel scale, reduced-motion pointer placement, rendered pointer export, result status, and run exclusion.
- `scripts/check-cli.py`: real entry-point startup, script validation, bad flags, and a missing-app failed result.
- `scripts/check-runs.py`: failed expectations prevent later narration; cancellation preserves a cancelled MP4; concurrent demos are refused; live-only does not capture; asset/output paths containing spaces, `#`, and `:` work.
- `scripts/check-install.py`: source install, reinstall, corrupt-cache rejection with blocked network, and preservation of the prior app/CLI/skill all passed.
- The default installer completed at `~/Applications/Showback.app`, `~/.local/bin/showback`, and `~/.agents/skills/showback`. Its installed doctor found the model and reported Accessibility and Screen Recording granted.
- `scripts/check-settings.py`: the native Settings window recovered an invalid saved voice, selected Marius through the accessibility contract, persisted that selection, and closed cleanly. No voice preview was played.
- Capture loss now stops narration promptly and prevents later scenes. The regression first reproduced a falsely completed run after its window closed, then passed with source visibility monitoring and capture-error cancellation.
- A native fixture walkthrough produced a completed 760 × 540 H.264/AAC MP4 with three checked scene screenshots. Pointer placement and image density were inspected visually after fixing a scale error.
- A local WebKit browser walkthrough produced a completed 900 × 620 H.264/AAC MP4. Its checked welcome state and cursor were inspected visually.
- An explicit display-scoped two-app walkthrough produced a completed 1,280 × 800 H.264/AAC MP4. App switching worked; the source excluded Showback's controls and used one rendered cursor.
- The compact model generated 7.08 seconds of test speech in 0.83 seconds total; standard English generated 6.68 seconds in 1.82 seconds. This is a single local measurement, not a benchmark claim.
- On-device transcription recovered the complete native exported narration through its final sentence. The compact model's first short synthesis check preserved the intended UI instructions; the standard model did not improve that check.

## Checks still pending

- Stop-button interaction, moving targets/windows, and occluding-window exclusion.
- Offline run with outbound IP networking denied, and measured synchronization against recorded UI changes.
- Fresh review and final requirement audit.

The build targets macOS 15+. Intel runtime assets require AVX2; Intel and macOS 15 hardware behavior remain unverified. Test fixtures are not evidence that a specific user's application or project tests pass.
